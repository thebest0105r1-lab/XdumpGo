// Package engine es el motor de XDumpGO 3.0 PREMIUM:
// generator de dorks por patrones, scraper multi-motor,
// explotador SQLi, dumper de BD/paginas, autosheller y core.
package engine

import (
"context"
"encoding/json"
"fmt"
"net/http"
"os"
"os/exec"
"path/filepath"
"runtime"
"strconv"
"strings"
"sync"
"sync/atomic"
"time"
)

// AppVersion: version visible (titulo + self-test).
const AppVersion = "3.0"

const maxBodyBytes = 4 * 1024 * 1024 // tope de 4 MB por respuesta

// ---------- Config (mismo esquema que el config.json del original) ----------

type AutoShellCfg struct {
Asp bool `json:"asp"`
Php bool `json:"php"`
}

type CoreCfg struct {
BatchMode bool `json:"batchmode"`
Threads   int  `json:"threads"`
Timeouts  int  `json:"timeouts"`
}

type DumperCfg struct {
KeepBlanks  bool `json:"keepblanks"`
MinRowCount int  `json:"minrowcount"`
MinRows     bool `json:"minrows"`
Targeted    bool `json:"targeted"`
Usedios     bool `json:"usedios"`
}

type DBMSCfg struct {
Mssql       bool `json:"mssql"`
Mysql      bool `json:"mysql"`
Oracle     bool `json:"oracle"`
Postgresql bool `json:"postgresql"`
}

type TechCfg struct {
Blind   bool `json:"blind"`
Error   bool `json:"error"`
Stacked bool `json:"stacked"`
Union   bool `json:"union"`
}

type ExploiterCfg struct {
DBMS       DBMSCfg  `json:"dbms"`
Heuristics bool     `json:"heuristics"`
Intensity  int      `json:"intensity"`
Techniques TechCfg  `json:"techniques"`
}

type ParamDef struct {
Data     []string `json:"Data"`
FilePath string   `json:"FilePath"`
Name     string   `json:"Name"`
Prefix   string   `json:"Prefix"`
}

type GeneratorCfg struct {
Limit      bool       `json:"limit"`
Max        int        `json:"max"`
Parameters []ParamDef `json:"parameters"`
Patterns   []string   `json:"patterns"`
}

type EnginesCfg struct {
Aol         bool `json:"aol"`
Bing        bool `json:"bing"`
Duckduckgo  bool `json:"duckduckgo"`
Ecosia      bool `json:"ecosia"`
Google      bool `json:"google"`
Googleapi   bool `json:"googleapi"`
Mywebsearch bool `json:"mywebsearch"`
Qwant       bool `json:"qwant"`
Startpage   bool `json:"startpage"`
Yahoo       bool `json:"yahoo"`
Yandex      bool `json:"yandex"`
}

type ScraperCfg struct {
Engines EnginesCfg `json:"engines"`
Filter  bool       `json:"filter"`
Pages   int        `json:"pages"`
}

// Config: raiz de config.json (compatible con el original).
type Config struct {
Autosheller AutoShellCfg `json:"autosheller"`
Core        CoreCfg      `json:"core"`
Dumper      DumperCfg    `json:"dumper"`
Exploiter   ExploiterCfg `json:"exploiter"`
Generator   GeneratorCfg `json:"generator"`
Scraper     ScraperCfg   `json:"scraper"`
}

// DefaultConfig replica los valores del config.json del original.
func DefaultConfig() Config {
return Config{
Autosheller: AutoShellCfg{Asp: false, Php: true},
Core:        CoreCfg{BatchMode: false, Threads: 100, Timeouts: 10},
Dumper:      DumperCfg{KeepBlanks: false, MinRowCount: 500, MinRows: false, Targeted: false, Usedios: true},
Exploiter: ExploiterCfg{
DBMS:       DBMSCfg{Mssql: true, Mysql: true, Oracle: true, Postgresql: true},
Heuristics: true,
Intensity:  2,
Techniques: TechCfg{Blind: false, Error: true, Stacked: false, Union: true},
},
Generator: GeneratorCfg{
Limit: true,
Max:   50000,
Parameters: []ParamDef{
{FilePath: "kw.txt", Name: "Keywords", Prefix: "(KW)"},
{FilePath: "pf.txt", Name: "Page Formats", Prefix: "(PF)"},
{FilePath: "pt.txt", Name: "Page Types", Prefix: "(PT)"},
{FilePath: "pp.txt", Name: "Page Parameter", Prefix: "(PP)"},
{FilePath: "sf.txt", Name: "Search Functions", Prefix: "(SF)"},
{FilePath: "de.txt", Name: "Domains", Prefix: "(DE)"},
},
Patterns: []string{
"(KW).(PT)?(PP)=",
"(KW) / php?(PP)=",
`"(KW)" / (DE).(PT)?(PP)=`,
`.(PT)? "(KW)" / (DE) (PP)=`,
`(KW)? "(DE)"`,
},
},
Scraper: ScraperCfg{
Engines: EnginesCfg{},
Filter:  true,
Pages:   2,
},
}
}

// ---------- Tipos de resultados ----------

type Dork struct {
ID      int    `json:"id"`
Text    string `json:"text"`
Pattern string `json:"pattern"`
}

type URLItem struct {
ID     int      `json:"id"`
Raw    string   `json:"raw"`
Host   string   `json:"host"`
Path   string   `json:"path"`
Params []string `json:"params"`
Engine string   `json:"engine"`
Dork   string   `json:"dork"`
Status int      `json:"status"`
OK     bool     `json:"ok"`
}

type Exploit struct {
ID        int    `json:"id"`
URL       string `json:"url"`
Param     string `json:"param"`
Technique string `json:"technique"`
DBMS      string `json:"dbms"`
Version   string `json:"version"`
Finding   string `json:"finding"`
}

type Dump struct {
ID       int      `json:"id"`
URL      string   `json:"url"`
Mode     string   `json:"mode"` // db|page
DBMS     string   `json:"dbms"`
Tables   []string `json:"tables"`
Rows     int      `json:"rows"`
Title    string   `json:"title"`
Emails   []string `json:"emails"`
Links    []string `json:"links"`
JSFiles  []string `json:"jsFiles"`
Secrets  []string `json:"secrets"`
Comments []string `json:"comments"`
Status   int      `json:"status"`
Size     int      `json:"size"`
}

type ShellOut struct {
Cmd  string `json:"cmd"`
Out  string `json:"out"`
Err  string `json:"err"`
Exit int    `json:"exit"`
}

type LogEntry struct {
TS   string `json:"ts"`
Kind string `json:"kind"`
Msg  string `json:"msg"`
}

type JobStat struct {
Name   string  `json:"name"`
Done   int64   `json:"done"`
Total  int     `json:"total"`
Speed  float64 `json:"speed"`
Active bool    `json:"active"`
}

type Stats struct {
Running    bool    `json:"running"`
Job        JobStat `json:"job"`
ElapsedSec float64 `json:"elapsedSec"`
Dorks      int     `json:"dorks"`
URLs       int     `json:"urls"`
Exploits   int     `json:"exploits"`
Dumps      int     `json:"dumps"`
Shell      int     `json:"shell"`
Version    string  `json:"version"`
}

type Resp struct {
OK    bool   `json:"ok"`
Error string `json:"error,omitempty"`
Count int    `json:"count,omitempty"`
Path  string `json:"path,omitempty"`
Data  string `json:"data,omitempty"`
}

// ---------- Motor ----------

type Engine struct {
mu       sync.Mutex
config   Config
dorks    []Dork
urls     []URLItem
urlSeen  map[string]bool
exploits []Exploit
dumps    []Dump
shellOut []ShellOut
logs     []LogEntry
jobName  string
jobTotal int
done     int64
start    time.Time
client   *http.Client
bufPool  *sync.Pool
ctx      context.Context
cancel   context.CancelFunc
}

// New crea el motor (carga config.json si existe, como el original).
func New() *Engine {
ctx, cancel := context.WithCancel(context.Background())
e := &Engine{
ctx:     ctx,
cancel:  cancel,
urlSeen: make(map[string]bool),
logs:    make([]LogEntry, 0, 512),
bufPool: &sync.Pool{New: func() any { return make([]byte, 32*1024) }},
}
e.config = e.loadConfig()
e.client = newClient(e.config.Core)
e.start = time.Now()
e.log("ok", "Motor XDumpGO " + AppVersion + " PREMIUM inicializado")
return e
}

// ---------- Helpers ----------

func marshal(v any) string {
b, err := json.Marshal(v)
if err != nil {
return `{"ok":false,"error":"` + strings.ReplaceAll(err.Error(), `"`, "'") + `"}`
}
return string(b)
}

// cfg devuelve el config actual (metodo distinto del campo "config").
func (e *Engine) cfg() Config {
e.mu.Lock()
defer e.mu.Unlock()
return e.config
}

func (e *Engine) log(kind, msg string) {
e.mu.Lock()
e.logs = append(e.logs, LogEntry{
TS:   time.Now().Format("15:04:05"),
Kind: kind,
Msg:  msg,
})
if len(e.logs) > 1000 {
e.logs = e.logs[len(e.logs)-1000:]
}
e.mu.Unlock()
}

func (e *Engine) startJob(name string, total int) context.Context {
e.mu.Lock()
if e.ctx.Err() == nil {
e.cancel()
}
e.ctx, e.cancel = context.WithCancel(context.Background())
e.jobName = name
e.jobTotal = total
atomic.StoreInt64(&e.done, 0)
e.start = time.Now()
ctx := e.ctx
e.mu.Unlock()
e.log("info", fmt.Sprintf("Job %q iniciado (%d elementos)", name, total))
return ctx
}

func (e *Engine) endJob(name string) {
e.mu.Lock()
if e.ctx.Err() == nil {
e.cancel()
}
e.mu.Unlock()
e.log("ok", fmt.Sprintf("Job %q finalizado", name))
}

// parallel ejecuta fn(0..total-1) con `workers` goroutines.
func (e *Engine) parallel(ctx context.Context, workers, total int, fn func(ctx context.Context, i int)) {
if workers < 1 {
workers = 1
}
sem := make(chan struct{}, workers)
var wg sync.WaitGroup
for i := 0; i < total; i++ {
if ctx.Err() != nil {
break
}
wg.Add(1)
sem <- struct{}{}
go func(i int) {
defer wg.Done()
defer func() { <-sem }()
fn(ctx, i)
}(i)
}
wg.Wait()
}

func (e *Engine) markURL(id, status int) {
e.mu.Lock()
for i := range e.urls {
if e.urls[i].ID == id {
e.urls[i].Status = status
e.urls[i].OK = status >= 200 && status < 400
break
}
}
e.mu.Unlock()
}

// ---------- HTTP ----------

func newClient(core CoreCfg) *http.Client {
to := core.Timeouts
if to <= 0 {
to = 10
}
tr := &http.Transport{
MaxIdleConns:          400,
MaxIdleConnsPerHost:   200,
IdleConnTimeout:       30 * time.Second,
TLSHandshakeTimeout:   10 * time.Second,
ExpectContinueTimeout: 1 * time.Second,
ForceAttemptHTTP2:     true,
}
return &http.Client{Transport: tr, Timeout: time.Duration(to) * time.Second}
}

func (e *Engine) fetch(ctx context.Context, rawURL, ua string) (int, string, error) {
req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
if err != nil {
return 0, "", err
}
req.Header.Set("User-Agent", ua)
req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
req.Header.Set("Accept-Language", "en-US,en;q=0.9,es;q=0.8")
resp, err := e.client.Do(req)
if err != nil {
return 0, "", err
}
defer resp.Body.Close()

buf := e.bufPool.Get().([]byte)
defer e.bufPool.Put(buf)

var sb strings.Builder
sb.Grow(64 * 1024)
for {
n, rerr := resp.Body.Read(buf)
if n > 0 {
sb.Write(buf[:n])
}
if rerr != nil {
break
}
if sb.Len() > maxBodyBytes {
break
}
}
return resp.StatusCode, sb.String(), nil
}

// ---------- Config (config.json, como el original) ----------

func configPath() string {
if exe, err := os.Executable(); err == nil {
return filepath.Join(filepath.Dir(exe), "config.json")
}
return "config.json"
}

func (e *Engine) loadConfig() Config {
b, err := os.ReadFile(configPath())
if err != nil {
return DefaultConfig()
}
var c Config
if json.Unmarshal(b, &c) != nil {
return DefaultConfig()
}
d := DefaultConfig()
if c.Core.Threads <= 0 {
c.Core.Threads = d.Core.Threads
}
if c.Core.Timeouts <= 0 {
c.Core.Timeouts = d.Core.Timeouts
}
if c.Generator.Max <= 0 {
c.Generator.Max = d.Generator.Max
}
if c.Scraper.Pages <= 0 {
c.Scraper.Pages = d.Scraper.Pages
}
if c.Exploiter.Intensity <= 0 {
c.Exploiter.Intensity = d.Exploiter.Intensity
}
if c.Dumper.MinRowCount <= 0 {
c.Dumper.MinRowCount = d.Dumper.MinRowCount
}
return c
}

// ConfigJSON devuelve el config actual (para la UI).
func (e *Engine) ConfigJSON() string {
e.mu.Lock()
defer e.mu.Unlock()
return marshal(e.config)
}

// SaveConfig guarda el config en memoria y en disco (config.json).
func (e *Engine) SaveConfig(s string) string {
var c Config
if err := json.Unmarshal([]byte(s), &c); err != nil {
return marshal(Resp{OK: false, Error: "JSON invalido: " + err.Error()})
}
e.mu.Lock()
e.config = c
e.client = newClient(c.Core)
e.mu.Unlock()
if err := os.WriteFile(configPath(), []byte(marshal(c)), 0o644); err != nil {
e.log("warn", "Config en memoria pero no en disco: " + err.Error())
} else {
e.log("ok", "Config guardado en " + configPath())
}
return marshal(Resp{OK: true})
}

// ---------- Estado / resultados ----------

func (e *Engine) StatsJSON() string {
e.mu.Lock()
defer e.mu.Unlock()
st := Stats{
Dorks:    len(e.dorks),
URLs:     len(e.urls),
Exploits: len(e.exploits),
Dumps:    len(e.dumps),
Shell:    len(e.shellOut),
Version:  AppVersion,
}
running := e.ctx.Err() == nil
st.Running = running
st.Job.Active = running
st.Job.Name = e.jobName
st.Job.Done = atomic.LoadInt64(&e.done)
st.Job.Total = e.jobTotal
if running && !e.start.IsZero() {
el := time.Since(e.start).Seconds()
st.ElapsedSec = el
if el > 0.05 {
st.Job.Speed = float64(st.Job.Done) / el
}
}
return marshal(st)
}

// ResultsJSON: dorks|urls|exploits|dumps|shell|logs.
func (e *Engine) ResultsJSON(kind string) string {
e.mu.Lock()
defer e.mu.Unlock()
switch strings.ToLower(strings.TrimSpace(kind)) {
case "dorks":
return marshal(e.dorks)
case "urls":
return marshal(e.urls)
case "exploits":
return marshal(e.exploits)
case "dumps":
return marshal(e.dumps)
case "shell":
return marshal(e.shellOut)
case "logs":
return marshal(e.logs)
default:
return marshal(Resp{OK: false, Error: "tipo desconocido: " + kind})
}
}

func (e *Engine) SendMsg(msg string) string {
e.log("info", strings.TrimSpace(msg))
return marshal(Resp{OK: true})
}

func (e *Engine) StopAll() string {
e.mu.Lock()
running := e.ctx.Err() == nil
if running {
e.cancel()
}
e.mu.Unlock()
if running {
e.log("warn", "StopAll: job cancelado")
}
return marshal(Resp{OK: true})
}

func (e *Engine) OpenFile(p string) string {
p = strings.TrimSpace(p)
if p == "" {
return marshal(Resp{OK: false, Error: "ruta vacia"})
}
var cmd *exec.Cmd
switch runtime.GOOS {
case "windows":
cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", p)
case "darwin":
cmd = exec.Command("open", p)
default:
cmd = exec.Command("xdg-open", p)
}
if err := cmd.Start(); err != nil {
return marshal(Resp{OK: false, Error: err.Error()})
}
go cmd.Wait()
return marshal(Resp{OK: true})
}

func (e *Engine) ExportFile(name, content string) string {
outDir := filepath.Join(filepath.Dir(configPath()), "exports")
name = filepath.Base(strings.TrimSpace(name))
if name == "" || name == "." {
name = time.Now().Format("export-20060102-150405.txt")
}
if err := os.MkdirAll(outDir, 0o755); err != nil {
return marshal(Resp{OK: false, Error: err.Error()})
}
p := filepath.Join(outDir, name)
if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
return marshal(Resp{OK: false, Error: err.Error()})
}
e.log("ok", "Exportado: " + p)
return marshal(Resp{OK: true, Path: p})
}

// StartShell ejecuta un comando local (async).
func (e *Engine) StartShell(cfg string) string {
var c struct {
Cmd  string   `json:"cmd"`
Args []string `json:"args"`
CWD  string   `json:"cwd"`
}
if err := json.Unmarshal([]byte(cfg), &c); err != nil {
return marshal(Resp{OK: false, Error: err.Error()})
}
if strings.TrimSpace(c.Cmd) == "" {
return marshal(Resp{OK: false, Error: "comando vacio"})
}
core := e.cfg().Core
ctx := e.startJob("shell", 1)
go func() {
defer e.endJob("shell")
cctx, cancel := context.WithTimeout(ctx, time.Duration(core.Timeouts)*time.Second)
defer cancel()
cmd := exec.CommandContext(cctx, c.Cmd, c.Args...)
if c.CWD != "" {
cmd.Dir = c.CWD
}
var outB, errB strings.Builder
cmd.Stdout = &outB
cmd.Stderr = &errB
err := cmd.Run()
exit := 0
if err != nil {
if ee, ok := err.(*exec.ExitError); ok {
exit = ee.ExitCode()
} else {
exit = -1
}
}
full := c.Cmd
if len(c.Args) > 0 {
full += " " + strings.Join(c.Args, " ")
}
e.mu.Lock()
e.shellOut = append(e.shellOut, ShellOut{Cmd: full, Out: outB.String(), Err: errB.String(), Exit: exit})
if len(e.shellOut) > 50 {
e.shellOut = e.shellOut[len(e.shellOut)-50:]
}
e.mu.Unlock()
atomic.AddInt64(&e.done, 1)
e.log("ok", "Shell: "+full+" (exit "+strconv.Itoa(exit)+")")
}()
return marshal(Resp{OK: true})
}