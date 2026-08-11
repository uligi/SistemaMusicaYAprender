# Instalación — BL-MVP-030B

Rama: `main`.

HEAD requerido:

`73fff5fe4982085ba090316c883587ef987e746f`

Extrae `BL-MVP-030B_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030b.ps1
```

Resultado esperado:

```text
OK: apps/web/tsconfig.app.tsbuildinfo restaurado por ser salida incremental rastreada.
OK: BL-MVP-030B aplicado y validado.
```

Si indica que el archivo ya estaba limpio también es válido.

Después ejecuta nuevamente:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

No usar `Skip*`. No hacer staging, commit ni push hasta GREEN completo.
