# BL-MVP-018 · Implementar tokens del sistema visual

## Ficha

- Fase: F0 — Cimientos.
- Épica: EP-02 — Sistema de diseño y cliente base.
- Tipo: Habilitador.
- Traza: UI; ACC; DI-MVP-15.
- Story Points: 5.
- Dependencias: BL-MVP-001 a BL-MVP-003.
- Resultado aceptable: color, tipografía, espaciado, radios, elevación y movimiento se consumen desde
  tokens versionados y documentados.

## Implementación

La versión inicial vive en `apps/web/src/styles/tokens/v1.css`. `index.css` consume la versión y deja
de mantener colores, familias tipográficas, escalas de espaciado, radios, elevación o movimiento como
valores visuales aislados.

La paleta conserva los roles semánticos del diseño de interfaz: índigo para acción/navegación, verde
para confirmación, ámbar para revisión y rojo para riesgo/bloqueo. La interfaz visible sigue siendo
sobria y clara; la marca definitiva permanece fuera del contrato.

La pila tipográfica incluye `Noto Sans` y `Noto Sans JP` con fallbacks. El ejemplo base contiene texto
japonés marcado con `lang="ja"` para mantener el contrato semántico desde F0.

`prefers-reduced-motion: reduce` lleva las duraciones no esenciales a cero.

## Evidencia automatizada

`scripts/frontend/verify-design-tokens.mjs` valida:

- valores semánticos documentados;
- escala 4/8/12/16/24/32/48/64;
- radios 10/14/18;
- objetivo táctil 44;
- pilas Noto Sans / Noto Sans JP;
- movimiento reducido;
- consumo real de todas las familias;
- ausencia de colores crudos en `index.css`;
- versión `v1` visible y documentada.

CI ejecuta este verificador antes del build frontend.

## Corrección BL-MVP-018A — UTF-8 y esquema claro

La primera validación visual en Windows mostró mojibake en `Música`, el texto japonés y palabras con
tilde. `index.html` ya declaraba UTF-8; la causa fue que Windows PowerShell 5.1 interpretó los literales
no ASCII incluidos dentro del propio script de aplicación antes de escribir `App.tsx`.

El apply ahora embebe `App.tsx` e `index.css` como Base64 y escribe los bytes UTF-8 directamente. El
verificador comprueba los literales Unicode esperados y rechaza marcadores comunes de mojibake.

La línea base visual del MVP es clara, por lo que `index.css` declara `color-scheme: only light`. Esto
evita que el auto-dark del navegador transforme automáticamente los tokens claros durante la validación.
