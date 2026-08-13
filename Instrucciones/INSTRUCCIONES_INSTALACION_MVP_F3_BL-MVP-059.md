# INSTRUCCIONES — BL-MVP-059

Base exacta requerida:

`26a6c46caeca96a01bc2d197cb8189a1ee48312e`

## 1. Extraer

Extraer el ZIP directamente sobre la raíz del repositorio `SistemaMusicaYAprender`.

No extraer dentro de una carpeta adicional.

## 2. Ejecutar

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\apply-bl-mvp-059.ps1
```

Para declarar LOCAL GREEN no usar `-SkipBrowserInstall`, `-SkipQualityGate` ni `-SkipSmoke`.

## 3. Resultado esperado

- base y rama `main` exactas;
- staging vacío;
- frontend y .NET compilan;
- Playwright focal BL058/059 GREEN;
- quality gate completa GREEN;
- Release GREEN;
- smoke real PostgreSQL/API GREEN;
- inventario exacto de 19 rutas;
- ningún `tsconfig.app.tsbuildinfo` residual;
- no `git add`, commit ni push.

## 4. Revisión visual posterior

Tras LOCAL GREEN se reinicia el stack normal.

Antes de staging en BL-MVP-059 se revisa de forma real:

- `/editorial/canciones/{recordingId}/sincronizacion` con una fuente DRAFT disponible.

Debe comprobarse que el video y el editor permanecen utilizables en la misma vista, que el marcado usa la posición real del reproductor, que la navegación por líneas no exige scroll continuo y que el borrador temporal puede guardarse sin publicar.

`UI-MVP-009` queda cubierta en este BL por E2E determinista y por el smoke del contrato público. La revisión visual real de `/aprender/{slug}` se difiere hasta el BL de publicación, cuando exista una canción publicada con slug y componente TIMING consumibles. Esa revisión diferida no bloquea el cierre de BL-MVP-059.

Cuando exista publicación real, debe comprobarse además que la línea cambia con el reproductor, el foco no se mueve, la ausencia de nivel TOKEN degrada a LINE y la ausencia de TIMING degrada a NONE sin bloquear el contenido propio.

No hacer staging hasta que la revisión visual ejecutable de UI-MVP-022 y el inventario pre-stage sean aprobados.


## Revisión visual BL-MVP-059E

En desktop/laptop confirmar que video y editor aparecen lado a lado, el panel de video permanece visible al recorrer el editor, el selector cambia de línea sin desplazar la página y los botones de inicio/fin usan la posición real del reproductor. En 320 px debe apilarse sin overflow.
