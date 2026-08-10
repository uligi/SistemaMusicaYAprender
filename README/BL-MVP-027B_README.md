# BL-MVP-027B — reconciliación del inventario de correctivos

## Motivo

BL-MVP-027A quedó GREEN:

- Prettier 3.9.6 aplicó el formato canónico a `PersonalAccountLoginPage.tsx`;
- `prettier --check` aprobó;
- TypeScript aprobó;
- `git diff --check` aprobó.

Al reejecutar `scripts/apply-bl-mvp-027.ps1`, la puerta se detuvo antes de ejecutar calidad porque el
inventario del instalador base todavía no reconocía los artefactos documentales/técnicos de 027A:

- `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-027A.md`
- `README/BL-MVP-027A_README.md`
- `scripts/apply-bl-mvp-027a.ps1`

Este bloqueo es exclusivamente de gobernanza del instalador.

## Corrección

BL-MVP-027B entrega una versión completa corregida de `scripts/apply-bl-mvp-027.ps1`. El inventario
permitido ahora combina:

- archivos propios de BL-MVP-027;
- artefactos correctivos 027A;
- artefactos correctivos 027B;
- los movimientos históricos de README ya verificados por hash.

Se incluyen también los propios artefactos B porque la extracción del ZIP los crea antes de volver a
ejecutar el instalador base; de lo contrario la puerta volvería a considerarlos "ajenos".

## Alcance

No cambia logout, CSRF, cookies, UI, PostgreSQL, CI, SQL maestro ni pruebas. Únicamente corrige el
inventario permitido de `apply-bl-mvp-027.ps1`.

Después de 027B debe reejecutarse BL-MVP-027 completo, sin opciones `Skip*`.
