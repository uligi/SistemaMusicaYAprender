# BL-MVP-021C — Corrección de comillas de cmd.exe en Windows

## Fallo observado

El tercer `apply-bl-mvp-021.ps1` sí logró arrancar el compilador TypeScript, pero `tsc` recibió el valor de `-p` con comillas literales incluidas:

```text
error TS5058: The specified path does not exist:
'C:/Users/ul13m/Documents/GitHub/SistemaMusicaYAprender/"C:/Users/ul13m/AppData/Local/Temp/.../tsconfig.runtime.json"'.
```

Esto demuestra que BL-MVP-021B ya solucionó el problema de arranque de `npm.cmd`; el fallo restante es exclusivamente el modo en que la ruta absoluta se construyó dentro de un único command string.

## Causa

BL-MVP-021B usaba:

```js
['/d', '/s', '/c', `npm.cmd exec -- tsc -p "${compilerConfigPath}"`];
```

Al pasar todo el comando como una única cadena a `cmd.exe`, la combinación de `/s`, `/c` y las comillas internas produjo una ruta literal con `"` que `tsc` resolvió relativa al repositorio.

## Corrección

BL-MVP-021C deja de construir una command string manual.

Ahora pasa el comando y cada argumento como elementos separados:

```js
['/d', '/c', 'npm.cmd', 'exec', '--', 'tsc', '-p', compilerConfigPath];
```

Node construye la línea de proceso y `cmd.exe` recibe la ruta como argumento, sin introducir comillas literales en el valor entregado a `tsc`.

También se elimina `/s`, porque ya no necesitamos su tratamiento especial de comillas.

## Alcance

No cambia:

- cliente HTTP;
- ProblemDetails;
- ETag;
- If-Match;
- reintentos;
- Idempotency-Key;
- caché;
- nginx;
- CI;
- dependencias;
- backend;
- SQL;
- migraciones.

Solo cambia el lanzamiento de `tsc` dentro del verificador BL-MVP-021.

## Diagnóstico mejorado

Se conserva la mejora BL-MVP-021B: si el compilador vuelve a fallar, se muestran:

- spawn error;
- stdout;
- stderr;
- status;
- signal.

Por tanto, cualquier siguiente fallo mostrará el diagnóstico real.
