# Instalación — BL-MVP-031F

Base requerida:

`3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af`

Rama: `main`.

Extrae `BL-MVP-031F_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-031f.ps1
```

Resultado esperado:

```text
OK: archivos 031F formateados.
OK: TypeScript web aprobado.
OK: TypeScript E2E aprobado.
OK: E2E BL-MVP-031 confirma feedback visible, grant y revoke.
OK: git diff --check aprobado.
OK: BL-MVP-031F aplicado y validado.
```

Después ejecuta nuevamente:

```powershell
.\scripts\apply-bl-mvp-031.ps1
```

Sin `Skip*`. No ejecutar `git add`, commit ni push hasta GREEN local completo y revisión de
inventario.
