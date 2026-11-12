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