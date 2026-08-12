# Instalación BL-MVP-040

Base requerida:

`7c4efd50a7c4039a58429745fa4c04a53c40f959`

1. Extraer el ZIP en la raíz del repositorio.
2. Ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-040.ps1
```

3. No ejecutar `git add`, commit ni push hasta revisar la salida completa.
4. Si la puerta local queda verde, reiniciar el entorno con `scripts/local/stop.ps1` y `scripts/local/start.ps1` usando `-ExecutionPolicy Bypass`, y revisar visualmente UI-MVP-020.
