# Instrucciones — BL-MVP-042

1. Extraer el ZIP en la raíz de `SistemaMusicaYAprender`.
2. Confirmar que `main` apunta al SHA base requerido y que no hay staging.
3. Ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scriptspply-bl-mvp-042.ps1
```

4. No ejecutar `git add`, commit ni push.
5. Compartir la salida completa para revisar quality, smoke e inventario.
6. Al ser UI-MVP-002/003 visible, después del GREEN local se requiere reinicio normal y revisión visual antes de staging.
