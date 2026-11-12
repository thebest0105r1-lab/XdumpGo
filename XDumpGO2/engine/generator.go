package engine

import (
"encoding/json"
"fmt"
"os"
"path/filepath"
"regexp"
"strings"
)

// GenCfg: listas inline desde la UI (vacio => config.json / archivos txt / defaults).
type GenCfg struct {
KW       []string `json:"kw"`
PF       []string `json:"pf"`
PT       []string `json:"pt"`
PP       []string `json:"pp"`
SF       []string `json:"sf"`
DE       []string `json:"de"`
Patterns []string `json:"patterns"`
Max      int      `json:"max"`
}

var reTok = regexp.MustCompile(`\(([A-Z]{2})\)`)

type seg struct {
kind int // 0 literal, 1 placeholder
text string
opt  bool
}

func tokenize(pat string) []seg {
var out []seg
last := 0
for _, m := range reTok.FindAllStringSubmatchIndex(pat, -1) {
lit := pat[last:m[0]]
if lit != "" {
if strings.HasSuffix(lit, "?") {
out = append(out, seg{kind: 0, text: strings.TrimSuffix(lit, "?"), opt: true})
} else {
out = append(out, seg{kind: 0, text: lit})
}
}
opt := m[1] < len(pat) && pat[m[1]-1] == '?'
out = append(out, seg{kind: 1, text: pat[m[2]:m[3]], opt: opt})
last = m[1]
}
if rest := pat[last:]; rest != "" {
if strings.HasSuffix(rest, "?") {
out = append(out, seg{kind: 0, text: strings.TrimSuffix(rest, "?"), opt: true})
} else {
out = append(out, seg{kind: 0, text: rest})
}
}
return out
}

// variants resuelve los segmentos opcionales (2^k plantillas).
func variants(toks []seg) [][]seg {
var out [][]seg
var rec func(i int, cur []seg)
rec = func(i int, cur []seg) {
if i == len(toks) {
out = append(out, append([]seg{}, cur...))
return
}
s := toks[i]
if s.opt {
rec(i+1, cur)
rec(i+1, append(cur, s))
} else {
rec(i+1, append(cur, s))
}
}
rec(0, nil)
return out
}

func cleanDork(t string) string {
t = strings.Join(strings.Fields(t), " ")
return strings.TrimSpace(t)
}

// fillVariant llena los placeholders (producto cartesiano).
func fillVariant(v []seg, lists map[string][]string) []string {
var slots []seg
var phLists [][]string
for _, s := range v {
slots = append(slots, s)
if s.kind == 1 {
phLists = append(phLists, lists[s.text])
}
}
if len(phLists) == 0 {
var b strings.Builder
for _, s := range slots {
b.WriteString(s.text)
}
if t := cleanDork(b.String()); t != "" {
return []string{t}
}
return nil
}
for _, l := range phLists {
if len(l) == 0 {
return nil
}
}
total := 1
for _, l := range phLists {
total *= len(l)
}
idx := make([]int, len(phLists))
var res []string
for n := 0; n < total; n++ {
var b strings.Builder
ph := 0
for _, s := range slots {
if s.kind == 1 {
b.WriteString(phLists[ph][idx[ph]])
ph++
} else {
b.WriteString(s.text)
}
}
if t := cleanDork(b.String()); t != "" {
res = append(res, t)
}
for k := len(phLists) - 1; k >= 0; k-- {
idx[k]++
if idx[k] < len(phLists[k]) {
break
}
idx[k] = 0
}
}
return res
}

// expandPattern genera todas las dorks de un patron.
func expandPattern(pat string, lists map[string][]string) []string {
seen := make(map[string]bool)
var out []string
for _, v := range variants(tokenize(pat)) {
for _, t := range fillVariant(v, lists) {
if !seen[t] {
seen[t] = true
out = append(out, t)
}
}
}
return out
}

func readListFile(p string) []string {
b, err := os.ReadFile(p)
if err != nil {
return nil
}
var out []string
for _, ln := range strings.Split(string(b), "\n") {
if ln = strings.TrimSpace(strings.TrimSuffix(ln, "\r")); ln != "" {
out = append(out, ln)
}
}
return out
}

var defaultLists = map[string][]string{
"KW": {"admin", "login", "config", "backup", "db", "database", "phpmyadmin", "wp-admin", "intranet", "portal", "panel", "user", "secret", "api", "test", "demo"},
"PF": {"php", "asp", "aspx", "jsp", "cfm", "pl", "py", "cgi"},
"PT": {"htm", "html", "php", "asp", "jsp", "xml", "txt", "csv", "json", "sql", "bak"},
"PP": {"id", "page", "cat", "p", "s", "q", "search", "file", "doc", "item", "num", "no"},
"SF": {"inurl:", "intitle:", "site:", "intext:"},
"DE": {},
}

func (e *Engine) paramLists(c GenCfg) map[string][]string {
cfg := e.cfg()
inline := map[string][]string{
"KW": c.KW, "PF": c.PF, "PT": c.PT, "PP": c.PP, "SF": c.SF, "DE": c.DE,
}
lists := make(map[string][]string)
for _, p := range cfg.Generator.Parameters {
code := strings.TrimPrefix(strings.TrimSuffix(p.Prefix, ")"), "(")
l := inline[code]
if len(l) == 0 {
l = p.Data
}
if len(l) == 0 && p.FilePath != "" {
l = readListFile(filepath.Join(filepath.Dir(configPath()), p.FilePath))
}
if len(l) == 0 {
l = defaultLists[code]
}
lists[code] = l
}
return lists
}

// GenDorks genera dorks por patrones (sin duplicados) y las guarda en el motor.
func (e *Engine) GenDorks(cfg string) string {
var c GenCfg
if err := json.Unmarshal([]byte(cfg), &c); err != nil {
return marshal(Resp{OK: false, Error: "JSON invalido: " + err.Error()})
}
conf := e.cfg()
pats := c.Patterns
if len(pats) == 0 {
pats = conf.Generator.Patterns
}
max := c.Max
if max <= 0 {
max = conf.Generator.Max
}
if max <= 0 {
max = 50000
}
lists := e.paramLists(c)

seen := make(map[string]bool)
var out []Dork
add := func(text, pat string) {
if text == "" || seen[text] {
return
}
seen[text] = true
out = append(out, Dork{ID: len(out), Text: text, Pattern: pat})
}
for _, pat := range pats {
for _, t := range expandPattern(pat, lists) {
add(t, pat)
if conf.Generator.Limit && len(out) >= max {
goto done
}
}
}
done:
if len(out) == 0 {
return marshal(Resp{OK: false, Error: "sin dorks: revisa patrones y listas"})
}
e.mu.Lock()
e.dorks = out
e.mu.Unlock()
e.log("ok", fmt.Sprintf("%d dorks generadas (%d patrones)", len(out), len(pats)))
return marshal(Resp{OK: true, Count: len(out)})
}