# BL-MVP-022 — Preparar arnés Playwright, axe y pruebas visuales

## Definición normativa

- Fase: F0 — Cimientos
- Épica: EP-02 — Sistema de diseño y cliente base
- Tipo: Habilitador
- Traza: ACC; MAN; CE-13
- Story Points: 5
- Dependencias: BL-MVP-004, BL-MVP-019 y BL-MVP-020
- Resultado aceptable: **“CI ejecuta navegación base a 320 px, teclado, axe y capturas de estados sin depender de datos manuales.”**

## Implementación

- Playwright Test 1.62.0 fijado en el lockfile del repositorio.
- `@axe-core/playwright` 4.11.3.
- Chromium como navegador del arnés base.
- viewport 320 × 800 CSS px.
- navegación real `/` → `/canciones` mediante teclado.
- comprobación de foco visible y ausencia de overflow horizontal.
- axe sobre inicio, catálogo, sesión requerida y ruta no disponible.
- capturas de estados y evidencia JSON en `artifacts/e2e/`.
- sin cuentas, canciones, base precargada ni datos manuales.
- CI instala Chromium con dependencias y publica la evidencia dentro del artifact existente.

## Fuera de alcance

BL-MVP-022 no implementa pantallas funcionales nuevas, no cambia backend, SQL, migraciones, roles, autorización ni datos. La primera pantalla funcional continúa en BL-MVP-023.

La auditoría axe no sustituye pruebas manuales de accesibilidad; solo automatiza la parte verificable por reglas del navegador.
