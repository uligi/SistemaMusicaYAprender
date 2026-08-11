# Instalación — BL-MVP-031H

Base requerida:

`3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af`

Rama: `main`.

Extrae `BL-MVP-031H_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-031h.ps1
```

Resultado esperado:

```text
OK: archivos 031H formateados.
OK: TypeScript web aprobado.
OK: TypeScript E2E aprobado.
OK: E2E BL-MVP-031 confirma grant/revoke y feedback visible.
OK: git diff --check aprobado.
OK: BL-MVP-031H aplicado y validado.
```

Después ejecuta nuevamente la puerta completa:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-031.ps1
```

Sin `Skip*`. No ejecutar `git add`, commit ni push hasta GREEN local completo y revisión de
inventario.
