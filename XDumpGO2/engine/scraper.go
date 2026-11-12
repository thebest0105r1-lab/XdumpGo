package engine

import (
"context"
"encoding/json"
"fmt"
"html"
"net/url"
"regexp"
"strconv"
"strings"
"sync/atomic"
)

// ScrapeCfg: motores a usar (vacio => config.json), paginas, workers.
type ScrapeCfg struct {
Engines EnginesCfg `json:"engines"`
Pages   int        `json:"pages"`
Workers int        `json:"workers"`
Filter  *bool      `json:"filter"`
Dorks   []string   `json:"dorks"`
}

type engineDef struct {
name   string
build  func(q string, page int) string
extract func(body string) []string
}

var (
reGoogleURL  = regexp.MustCompile(`href="(/url\?q=([^&"<>]+))"`)
reGoogleAbs  = regexp.MustCompile(`href="(https?://[^"]+)"`)
reBingResult = regexp.MustCompile(`(?s)<h2[^>]*>\s*<a[^>]+href="([^"]+)"`)
reDuckLink   = regexp.MustCompile(`uddg=([^&"<>]+)`)
reAbsLink    = regexp.MustCompile(`href="(https?://[^"]+)"`)
)

var noiseHosts = map[string]bool{
"google.com": true, "googleapis.com": true, "gstatic.com": true,
"ggpht.com": true, "googleusercontent.com": true, "youtube.com": true,
"bing.com": true, "microsoft.com": true, "msn.com": true,
"w3.org": true, "schema.org": true, "ytimg.com": true,
"duckduckgo.com": true, "yahoo.com": true, "yimg.com": true,
"aol.com": true, "ecosia.org": true, "qwant.com": true,
"startpage.com": true, "yandex.com": true, "mywebsearch.com": true,
}

func extractGeneric(body string) []string {
seen := make(map[string]bool)
var out []string
for _, m := range reAbsLink.FindAllStringSubmatch(body, -1) {
s := html.UnescapeString(strings.TrimSpace(m[1]))
if s == "" || seen[s] {
continue
}
seen[s] = true
out = append(out, s)
}
return out
}

func extractGoogle(body string) []string {
seen := make(map[string]bool)
var out []string
add := func(s string) {
s = html.UnescapeString(strings.TrimSpace(s))
if s == "" || seen[s] {
return
}
seen[s] = true
out = append(out, s)
}
for _, m := range reGoogleURL.FindAllStringSubmatch(body, -1) {
if u, err := url.QueryUnescape(m[2]); err == nil {
add(u)
}
}
if len(out) == 0 {
for _, m := range reGoogleAbs.FindAllStringSubmatch(body, -1) {
low := strings.ToLower(m[1])
if strings.Contains(low, "google.") || strings.Contains(low, "gstatic") ||
strings.Contains(low, "youtube.com") {
continue
}
add(m[1])
}
}
return out
}

func extractBing(body string) []string {
seen := make(map[string]bool)
var out []string
for _, m := range reBingResult.FindAllStringSubmatch(body, -1) {
s := html.UnescapeString(strings.TrimSpace(m[1]))
if s != "" && !seen[s] {
seen[s] = true
out = append(out, s)
}
}
if len(out) == 0 {
out = extractGeneric(body)
}
return out
}

func extractDuck(body string) []string {
seen := make(map[string]bool)
var out []string
for _, m := range reDuckLink.FindAllStringSubmatch(body, -1) {
if u, err := url.QueryUnescape(m[1]); err == nil && u != "" && !seen[u] {
seen[u] = true
out = append(out, u)
}
}
if len(out) == 0 {
out = extractGeneric(body)
}
return out
}

func enginesList() []engineDef {
return []engineDef{
{"google", func(q string, p int) string {
return "https://www.google.com/search?q=" + url.QueryEscape(q) + "&num=20&start=" + strconv.Itoa((p-1)*20)
}, extractGoogle},
{"googleapi", func(q string, p int) string {
return "https://www.google.com/search?q=" + url.QueryEscape(q) + "&num=20&start=" + strconv.Itoa((p-1)*20) + "&ie=UTF-8"
}, extractGoogle},
{"bing", func(q string, p int) string {
return "https://www.bing.com/search?q=" + url.QueryEscape(q) + "&first=" + strconv.Itoa((p-1)*10+1)
}, extractBing},
{"duckduckgo", func(q string, p int) string {
return "https://html.duckduckgo.com/html/?q=" + url.QueryEscape(q) + "&s=" + strconv.Itoa((p-1)*30)
}, extractDuck},
{"yahoo", func(q string, p int) string {
return "https://search.yahoo.com/search?p=" + url.QueryEscape(q) + "&b=" + strconv.Itoa((p-1)*10+1)
}, extractGeneric},
{"aol", func(q string, p int) string {
return "https://search.aol.com/aol/search?q=" + url.QueryEscape(q)
}, extractGeneric},
{"ecosia", func(q string, p int) string {
return "https://www.ecosia.org/search?q=" + url.QueryEscape(q) + "&page=" + strconv.Itoa(p)
}, extractGeneric},
{"startpage", func(q string, p int) string {
return "https://www.startpage.com/sp/search?query=" + url.QueryEscape(q)
}, extractGeneric},
{"qwant", func(q string, p int) string {
return "https://www.qwant.com/?q=" + url.QueryEscape(q)
}, extractGeneric},
{"yandex", func(q string, p int) string {
return "https://yandex.com/search/?text=" + url.QueryEscape(q) + "&p=" + strconv.Itoa(p-1)
}, extractGeneric},
{"mywebsearch", func(q string, p int) string {
return "https://search.mywebsearch.com/web/search?q=" + url.QueryEscape(q)
}, extractGeneric},
}
}

// StartScrape lanza el job de scraping (async): dorks x motores x paginas.
func (e *Engine) StartScrape(cfg string) string {
var c ScrapeCfg
if err := json.Unmarshal([]byte(cfg), &c); err != nil {
return marshal(Resp{OK: false, Error: err.Error()})
}
conf := e.cfg()
if c.Pages <= 0 {
c.Pages = conf.Scraper.Pages
}
if c.Pages < 1 {
c.Pages = 1
}
if c.Workers <= 0 {
c.Workers = conf.Core.Threads
}
filter := conf.Scraper.Filter
if c.Filter != nil {
filter = *c.Filter
}

var dorks []string
if len(c.Dorks) > 0 {
for _, d := range c.Dorks {
if d = strings.TrimSpace(d); d != "" {
dorks = append(dorks, d)
}
}
} else {
e.mu.Lock()
for _, d := range e.dorks {
dorks = append(dorks, d.Text)
}
e.mu.Unlock()
}
if len(dorks) == 0 {
return marshal(Resp{OK: false, Error: "sin dorks: generalas primero o pasalas en cfg.dorks"})
}

engines := enginesList()
var active []engineDef
for _, ed := range engines {
if c.Engines == (EnginesCfg{}) && c.Engines == conf.Scraper.Engines {
// cfg sin motores explicitos: usar config.json
}
on := false
switch ed.name {
case "aol":
on = c.Engines.Aol || conf.Scraper.Engines.Aol
case "bing":
on = c.Engines.Bing || conf.Scraper.Engines.Bing
case "duckduckgo":
on = c.Engines.Duckduckgo || conf.Scraper.Engines.Duckduckgo
case "ecosia":
on = c.Engines.Ecosia || conf.Scraper.Engines.Ecosia
case "google":
on = c.Engines.Google || conf.Scraper.Engines.Google
case "googleapi":
on = c.Engines.Googleapi || conf.Scraper.Engines.Googleapi
case "mywebsearch":
on = c.Engines.Mywebsearch || conf.Scraper.Engines.Mywebsearch
case "qwant":
on = c.Engines.Qwant || conf.Scraper.Engines.Qwant
case "startpage":
on = c.Engines.Startpage || conf.Scraper.Engines.Startpage
case "yahoo":
on = c.Engines.Yahoo || conf.Scraper.Engines.Yahoo
case "yandex":
on = c.Engines.Yandex || conf.Scraper.Engines.Yandex
}
if on {
active = append(active, ed)
}
}
if len(active) == 0 {
return marshal(Resp{OK: false, Error: "sin motores activos: marca al menos uno"})
}

type task struct {
dork   string
engine engineDef
page   int
}
var tasks []task
for _, d := range dorks {
for _, ed := range active {
for p := 1; p <= c.Pages; p++ {
tasks = append(tasks, task{d, ed, p})
}
}
}

ctx := e.startJob("scrape", len(tasks))
go func() {
defer e.endJob("scrape")
e.parallel(ctx, c.Workers, len(tasks), func(ctx context.Context, i int) {
t := tasks[i]
e.scrapeTask(ctx, t.dork, t.engine, t.page, filter)
atomic.AddInt64(&e.done, 1)
})
}()
return marshal(Resp{OK: true, Count: len(tasks)})
}

func (e *Engine) scrapeTask(ctx context.Context, dork string, ed engineDef, page int, filter bool) {
ua := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
status, body, err := e.fetch(ctx, ed.build(dork, page), ua)
if err != nil {
e.log("warn", "scrape: "+err.Error())
return
}
if status != 200 {
e.log("warn", fmt.Sprintf("scrape: HTTP %d en %s/%s", status, ed.name, dork))
return
}
n := 0
for _, raw := range ed.extract(body) {
if ctx.Err() != nil {
return
}
if e.addURL(raw, ed.name, dork, filter) {
n++
}
}
if n > 0 {
e.log("info", fmt.Sprintf("scrape: %d URLs nuevas de %s con %q", n, ed.name, dork))
}
}

func (e *Engine) addURL(raw, engineName, dork string, filter bool) bool {
u, err := url.Parse(strings.TrimSpace(raw))
if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
return false
}
host := strings.ToLower(u.Hostname())
if filter && noiseHosts[host] {
return false
}
key := host + u.Path
e.mu.Lock()
if e.urlSeen[key] {
e.mu.Unlock()
return false
}
e.urlSeen[key] = true
item := URLItem{
ID:     len(e.urls),
Raw:    u.String(),
Host:   host,
Path:   u.Path,
Params: paramNames(u),
Engine: engineName,
Dork:   dork,
}
e.urls = append(e.urls, item)
e.mu.Unlock()
return true
}

func paramNames(u *url.URL) []string {
seen := make(map[string]bool)
var out []string
for k := range u.Query() {
if !seen[k] {
seen[k] = true
out = append(out, k)
}
}
return out
}