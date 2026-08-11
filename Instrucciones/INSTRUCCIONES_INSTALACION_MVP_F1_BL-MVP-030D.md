# Instalación — BL-MVP-030D

Rama: `main`.

HEAD requerido:

`73fff5fe4982085ba090316c883587ef987e746f`

Extrae `BL-MVP-030D_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030d.ps1
```

Debe terminar con:

```text
OK: route-manifest formateado con Prettier 3.9.6.
OK: TypeScript aprobado.
OK: BL-MVP-030D aplicado y validado.
```

Después ejecuta nuevamente:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

Sin `Skip*`. No hacer staging, commit ni push hasta GREEN completo.
