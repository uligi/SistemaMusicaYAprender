# Instalación — BL-MVP-031K

Base publicada requerida:

`3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af`

Rama: `main`.

Extrae `BL-MVP-031K_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio.

El paquete ya usa la convención:

```text
Instrucciones/
README/
scripts/
```

Ejecuta:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-031k.ps1
```

El correctivo normaliza primero los archivos `INSTRUCCIONES_*.md` dentro de `Instrucciones/` y luego
ejecuta el smoke BL-MVP-031 contra el entorno local ya levantado.

Si termina con:

```text
OK: BL-MVP-031K aplicado y smoke BL-MVP-031 validado.
```

ejecuta la puerta completa:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-031.ps1
```

No usar `Skip*`. No ejecutar `git add`, commit ni push hasta GREEN local completo y revisión del
inventario.
