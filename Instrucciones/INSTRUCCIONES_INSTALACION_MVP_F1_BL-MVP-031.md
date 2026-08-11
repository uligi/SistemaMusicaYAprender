# Instalación — F1 / BL-MVP-031

Base publicada requerida:

`3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af`

Rama requerida: `main`.

Extrae `BL-MVP-031_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio, sin carpeta
envolvente.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-031.ps1
```

El instalador no ejecuta `git add`, commit ni push.

No usar opciones `Skip*`. Si la puerta queda RED, conservar la primera falla observada y corregirla
antes de continuar.
