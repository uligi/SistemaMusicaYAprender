# Pruebas E2E

BL-MVP-022 activa el arnés canónico de navegador con Playwright y axe. La suite usa rutas reales del app shell y estados ya definidos; no crea una pantalla de demostración ni necesita cuentas, canciones, semillas o datos manuales.

## Cobertura base

La suite `base-accessibility.spec.ts` ejecuta Chromium con viewport de **320 × 800 CSS px**, `es-CR`, modo claro y movimiento reducido. Comprueba:

- navegación base por teclado y foco visible;
- ausencia de desbordamiento horizontal de página a 320 px;
- semántica japonesa `lang="ja"` sobre el contenido de referencia existente;
- auditoría axe con etiquetas WCAG 2.x/2.1/2.2 AA aplicables;
- estado `UI-EST-07` de sesión requerida;
- estado `UI-EST-03` de ruta no disponible;
- capturas y JSON de axe en `artifacts/e2e/`.

## Primera preparación local

Desde la raíz del repositorio:

```powershell
npm.cmd ci
npm.cmd run test:e2e:install
npm.cmd run build
npm.cmd run test:e2e
```

`apply-bl-mvp-022.ps1` realiza esta preparación automáticamente. Después de instalar Chromium una vez, `scripts/check-quality.ps1` incorpora el arnés E2E a la puerta local.

## CI

CI instala únicamente Chromium y sus dependencias del runner, ejecuta `npm run test:e2e` con un worker y publica `artifacts/` dentro de la evidencia normal del workflow. La suite no depende de una base de datos precargada porque BL-MVP-022 valida el shell y estados deterministas existentes.

## Límite de la automatización

axe automatiza una parte de WCAG, no sustituye la prueba manual con teclado, lector de pantalla, zoom, percepción ni usabilidad. La evidencia automática de BL-MVP-022 complementa las revisiones manuales exigidas por los RNF de accesibilidad.
