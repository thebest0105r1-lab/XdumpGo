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