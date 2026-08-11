# Instalación BL-MVP-036

Base requerida:

`f65012126b438960d90e02ccb626216cf08a3f53`

Desde:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

1. Extraer `BL-MVP-036_Paquete_Instalacion.zip` directamente sobre la raíz.
2. Desbloquear los scripts si Windows añadió marca de procedencia.
3. Ejecutar el instalador con `ExecutionPolicy Bypass` solo para ese proceso.
4. No ejecutar `git add`, commit ni push hasta revisar el GREEN local y el inventario.

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-036.ps1
```

La puerta verifica toolchain, `restore --locked-mode`, formato, TypeScript, frontend, Playwright, .NET, arquitectura, límites modulares, siete servicios, regresiones existentes y el smoke real de BL-MVP-036.

Resultado esperado:

`OK: BL-MVP-036 instalado y validado localmente...`

El script no ejecuta `git add`, commit, push ni migraciones de producción.
