# Instalación — BL-MVP-031E

Base requerida:

`3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af`

Rama: `main`.

Extrae `BL-MVP-031E_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-031e.ps1
```

Resultado esperado:

```text
OK: archivos 031E formateados.
OK: TypeScript E2E aprobado.
OK: regresion E2E BL-MVP-031 aprobada con Motivo exacto.
OK: git diff --check aprobado.
OK: BL-MVP-031E aplicado y validado.
```

Después ejecuta nuevamente:

```powershell
.\scripts\apply-bl-mvp-031.ps1
```

Sin `Skip*`. No ejecutar `git add`, commit ni push hasta GREEN local completo y revisión de
inventario.
