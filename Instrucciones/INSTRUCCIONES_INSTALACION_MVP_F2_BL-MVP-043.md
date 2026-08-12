# Instalación · BL-MVP-043

Base exacta requerida: `f12d5328f53d08dfcfbe2849cbdd224bf11df358` en `main`.

1. Extraer `BL-MVP-043_Paquete_Instalacion.zip` sobre la raíz del repositorio.
2. Ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-043.ps1
```

3. Pegar la salida completa.
4. No ejecutar `git add`, `commit` ni `push` todavía.

El instalador no hace staging. Después de GREEN local se reinicia el entorno normal y se revisan visualmente `/canciones` y una ficha `/canciones/{slug}`. Solo después se inventaría y revisaría el staging explícito.
