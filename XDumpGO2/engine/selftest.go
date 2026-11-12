package engine

import (
"encoding/json"
"fmt"
"os"
"strings"
)

// SelfTest prueba todos los modulos sin abrir la UI.
// Uso: xdumpgo2.exe -test  (devuelve 0 si todo pasa).
func SelfTest() int {
fmt.Println("XDumpGO " + AppVersion + " PREMIUM — self-test")
e := New()
fail := 0
check := func(ok bool, name string) {
if ok {
fmt.Println("  [OK]   " + name)
return
}
fmt.Println("  [FAIL] " + name)
fail++
}

// 1) Generator: patrones del original.
r := parseResp(e.GenDorks(`{"kw":["admin"],"pt":["php"],"pp":["id"],"de":["example.com"],"max":500}`))
check(r.ok && r.count > 0, "generator: genera dorks por patrones")
found := false
e.mu.Lock()
for _, d := range e.dorks {
if d.Text == "admin.php id=" {
found = true
}
}
e.mu.Unlock()
check(found, `generator: patron "(KW).(PT)?(PP)=" => "admin.php id="`)

// 2) Scraper: parsers de google/bing/duckduckgo.
g := extractGoogle(`<a href="/url?q=https://t1.com/a?id=1&amp;b=2">x</a>`)
check(containsStr(g, "https://t1.com/a?id=1&b=2"), "scraper: parser Google (/url?q=)")
b := extractBing(`<h2><a href="https://t2.com/x?p=9">y</a></h2>`)
check(containsStr(b, "https://t2.com/x?p=9"), "scraper: parser Bing")
d := extractDuck(`<a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Ft3.com%2Fz%3Fk%3D1">z</a>`)
check(containsStr(d, "https://t3.com/z?k=1"), "scraper: parser DuckDuckGo (uddg)")

// 3) Exploiter: deteccion de DBMS por errores.
nm, ver := detectDBMS("You have an error in your MySQL syntax; check MySQL 5.7.30 manual")
check(nm == "mysql" && ver == "5.7.30", "exploiter: detecta MySQL + version en errores")
nm2, _ := detectDBMS("An error has occurred while processing your request. Microsoft SQL Native Client")
check(nm2 == "mssql", "exploiter: detecta MSSQL en errores")

// 4) Dumper: modo pagina (emails/secretos/titulo).
sample := `<title>Panel</title><p>contacto@ejemplo.com</p>` +
`<script src="/js/app.js"></script><!-- TODO revisar -->` +
`<input value="aws_access_key_id=AKIA1234567890ABCDEF">`
check(firstMatch(reTitle, sample) == "Panel", "dumper: extrae <title>")
check(containsStr(capped(reEmail.FindAllString(sample, 100), 100), "contacto@ejemplo.com"), "dumper: extrae emails")
check(containsStr(cappedAttr(reScript, sample, 100), "/js/app.js"), "dumper: extrae JS")
check(len(reSecret.FindAllString(sample, -1)) >= 1, "dumper: detecta secretos (AWS)")
check(numAfter("xxx xqz 12345 yyy", "xqz") == 12345, "dumper: numAfter (conteos)")

// 5) Autosheller: shells PHP/ASP.
check(strings.Contains(phpShell(), "eval"), "autosheller: shell PHP con eval")
check(strings.Contains(aspShell(), "Execute"), "autosheller: shell ASP con Execute")

// 6) Core: config compatible con el original.
var cfg Config
check(json.Unmarshal([]byte(e.ConfigJSON()), &cfg) == nil, "core: config JSON valido")
check(cfg.Core.Threads == 100 && cfg.Core.Timeouts == 10, "core: threads=100 timeouts=10 (como el original)")
check(cfg.Generator.Max == 50000 && len(cfg.Generator.Patterns) == 5, "core: generator max=50000 + 5 patrones originales")
check(cfg.Exploiter.DBMS.Mysql && cfg.Exploiter.Techniques.Union, "core: exploiter mysql+union activos por defecto")

// 7) Export.
r2 := parseResp(e.ExportFile("selftest.txt", "ok"))
check(r2.ok && r2.path != "", "export: escribe archivo en exports/")
if r2.ok {
os.Remove(r2.path)
}

// 8) Stop.
check(strings.Contains(e.StopAll(), `"ok":true`), "stop: StopAll responde ok")

if fail == 0 {
fmt.Println("SELFTEST OK (" + AppVersion + " PREMIUM) — todos los modulos operan")
return 0
}
fmt.Printf("SELFTEST FAIL: %d prueba(s) fallaron\n", fail)
return 1
}

func parseResp(s string) Resp {
var r Resp
json.Unmarshal([]byte(s), &r)
return r
}

func containsStr(xs []string, v string) bool {
for _, x := range xs {
if x == v {
return true
}
}
return false
}