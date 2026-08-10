# Arnés E2E, accesibilidad y evidencia visual · BL-MVP-022

## Contrato

BL-MVP-022 implementa el habilitador **Preparar arnés Playwright, axe y pruebas visuales**. Su resultado vinculante es que CI ejecute navegación base a 320 px, teclado, axe y capturas de estados sin depender de datos manuales.

El arnés vive en `tests/E2ETests/` y consume únicamente rutas reales del manifiesto UI-MVP-001-032. No agrega rutas de producto, no modifica autorización y no introduce datos sintéticos dentro de la aplicación para hacer pasar la prueba.

## Navegación y 320 px

La configuración fija un viewport de 320 × 800 CSS px. La prueba abre la ruta pública `UI-MVP-001`, comprueba el foco trasladado al encabezado de ruta, retrocede mediante `Shift+Tab` por controles reales, confirma `:focus-visible` y activa `Canciones` con `Enter` hasta `UI-MVP-002`.

En cada estado relevante se comparan `scrollWidth` e `innerWidth` para rechazar desbordamiento horizontal de página. La prueba también conserva la referencia japonesa `音楽で日本語を学ぶ` bajo `lang="ja"`.

## axe

`@axe-core/playwright` ejecuta reglas automatizables etiquetadas para WCAG 2.0/2.1/2.2 nivel A/AA. Una violación falla la prueba y el resultado de axe se adjunta como JSON. Los resultados `incomplete` también se conservan como evidencia para revisión, pero requieren evaluación humana.

La automatización no demuestra por sí sola conformidad WCAG completa. Se mantienen las pruebas manuales de teclado, lector de pantalla, zoom, movimiento, comprensión y usabilidad previstas por el proyecto.

## Evidencia visual y estados

Las capturas se generan durante la prueba, no son datos de entrada. Se conservan en:

- `artifacts/e2e/screenshots/home-320.png`;
- `artifacts/e2e/screenshots/keyboard-focus-canciones-320.png`;
- `artifacts/e2e/screenshots/catalog-320.png`;
- `artifacts/e2e/screenshots/session-required-320.png`;
- `artifacts/e2e/screenshots/route-not-found-320.png`.

Los estados protegidos se obtienen de comportamiento real y determinista del shell anónimo:

- `/preferencias` → `UI-EST-07`;
- ruta desconocida → `UI-EST-03`.

No se insertan cuentas, canciones ni registros manuales para producir esas evidencias.

## Ejecución

Local, después de instalar Chromium una vez:

```powershell
npm.cmd run build
npm.cmd run test:e2e
```

La puerta local completa es:

```powershell
.\scripts\check-quality.ps1
```

CI ejecuta `playwright install --with-deps chromium` después del build y antes de `npm run test:e2e`. El HTML report, JSON de axe, screenshots, JUnit y traces de fallo quedan bajo `artifacts/`, que ya forma parte del artifact estándar del workflow.

## Determinismo

- un solo proyecto Chromium para este habilitador;
- un worker;
- cero reintentos automáticos para no ocultar inestabilidad;
- locale `es-CR`;
- zona `America/Costa_Rica`;
- esquema claro;
- `prefers-reduced-motion: reduce`;
- preview Vite local sobre el build de producción.

La matriz multi-navegador completa pertenece a los controles de compatibilidad posteriores; BL-MVP-022 cubre específicamente ACC, MAN y CE-13.
