# Instalación BL-MVP-048

Base obligatoria:

`5f8781b9b5601020f2d103a31d97994807015a37`

1. Confirma que `HEAD` y `origin/main` están exactamente en la base indicada y que el árbol está limpio.
2. Copia `apply-bl-mvp-048-freeze-submit-package.ps1` a `scripts/`.
3. Ejecuta el instalador con PowerShell; usa `-ExecutionPolicy Bypass` si tu política local lo requiere.
4. El instalador valida blobs base antes de escribir y ejecuta `git diff --check`.
5. No ejecuta `git add`, commit, push ni crea ramas.
6. Conserva el instalador durante las puertas de calidad y elimínalo antes del staging final.
7. Después de instalar, la primera puerta es formato/typecheck/build; no avances a staging hasta cerrar verificadores y E2E.
