# Instalación BL-MVP-052

Base Git exacta requerida:

`f7ff536295b82d556ca589f5cf5fd7143d79a178`

1. Extraer el ZIP en la raíz de `SistemaMusicaYAprender`.
2. Desbloquear los scripts PowerShell.
3. Ejecutar `scripts/apply-bl-mvp-052.ps1`.
4. No hacer staging, commit ni push.
5. Después de GREEN local, reiniciar el stack y abrir un expediente DRAFT para la revisión visual.

La validación incluye compare-and-swap real en PostgreSQL, Playwright de guardando/guardado/conflicto, axe,
320 px, quality gate completo y build Release.
