# Instalación BL-MVP-047 + BL-MVP-079

Base obligatoria:

`3ffc6e195ed5a82ad9980ce50ab991020527b190`

1. Coloca el PS1 en `scripts/`.
2. Verifica que `HEAD`, `origin/main` y el árbol estén limpios.
3. Ejecuta mediante PowerShell con `-ExecutionPolicy Bypass` si tu política local exige scripts firmados.
4. El instalador no hace `git add`, commit, push ni crea ramas.
5. Conserva el instalador temporal durante las puertas y elimínalo antes del staging.
