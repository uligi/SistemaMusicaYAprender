# BL-MVP-019 · Componentes accesibles esenciales

## Alcance

Elemento: **Crear componentes accesibles esenciales** `[Habilitador]`.

Traza: `UI; ACC; DI-MVP-01-14`.

Dependencia: `BL-MVP-018`.

Resultado aceptable: botón, enlace, campo, select, diálogo, tabla, pestañas, alertas y estados funcionan
con teclado, foco y lector de pantalla.

## Implementación

Se agrega una capa `apps/web/src/components/ui` sin framework visual externo. Los componentes usan HTML
nativo siempre que existe una semántica adecuada y solo agregan ARIA para describir relaciones o
estados que el elemento nativo no expresa por sí solo.

El catálogo temporal de `App.tsx` permite inspeccionar todos los componentes y los doce estados
UI-EST-01 a UI-EST-12 antes de construir el AppShell de BL-MVP-020.

No se modifica backend, SQL, migraciones, secretos, dependencias npm ni lockfiles.

## Verificación automática

```powershell
node scripts/frontend/verify-design-tokens.mjs
node scripts/frontend/verify-accessible-components.mjs
npm.cmd run typecheck
npm.cmd run build
.\scripts\check-quality.ps1
```

CI ejecuta el verificador de componentes después del verificador de tokens visuales.

## Verificación manual

Después de `.\scripts\local\start.ps1` y `.\scripts\local\verify-running.ps1`, abrir
`http://localhost:5173` y comprobar teclado, foco, Escape/retorno de foco del diálogo, flechas/Home/End
de pestañas y reflujo a 320 px. La guía detallada está en
`docs/engineering/frontend/accessible-components.md`.

## Corrección BL-MVP-019A — compatibilidad del verificador de tokens

La primera aplicación de BL-MVP-019 detectó dos supuestos demasiado específicos heredados del
verificador de BL-MVP-018: exigía que la pantalla siguiera mostrando el título temporal
`Música y Aprender` y buscaba todas las familias de tokens únicamente dentro de `index.css`.

BL-MVP-019 legítimamente reemplaza esa pantalla temporal por el catálogo de componentes y mueve el
consumo de movimiento a `components/ui/ui.css`. El verificador de tokens se corrige sin debilitar el
contrato: ahora inspecciona todo el CSS consumidor bajo `apps/web/src`, mantiene la prohibición de
colores crudos, conserva la comprobación de japonés/UTF-8 y detecta mojibake en los archivos fuente.
