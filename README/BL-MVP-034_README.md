# BL-MVP-034 — Perfil básico y preferencias iniciales seguras

**Fase:** F1 — EP-04 Preferencias y configuración
**Tipo:** Historia · **SP:** 5
**Traza:** CU-MVP-04; UI-MVP-008; M01; CE-04, CE-08, CE-11
**Dependencias:** BL-MVP-023 y BL-MVP-035
**Base:** `8d143e2cb10b89537fb8be2763decc609237ea16`

Resultado: cada cuenta recibe español, ayudas y accesibilidad seguras sin mezclar credenciales con perfil o preferencias.

BL034 reutiliza `identity.user_profile`, `identity.preference_set` e `identity.preference_revision`. No agrega tablas ni modifica el SQL maestro. El perfil mínimo continúa separado de M18; las preferencias se guardan como revisiones tipadas, privadas por RLS y con una cabeza estable versionada.

El valor lingüístico P0 se valida contra `LANGUAGE/ES` publicado por M19. El contrato inicial ofrece español para interfaz y traducción, presentación japonesa configurable, privacidad `PRIVATE`, movimiento reducido y protección contra destellos como defaults seguros. Los códigos no publicados o retirados no sustituyen la última revisión confirmada.

`/preferencias` deja de ser placeholder y permite consultar/confirmar la revisión propia con CSRF, concurrencia optimista y continuidad entre sesiones. No se persisten correo, contraseña, token, credencial ni secreto dentro del JSON de preferencias.

Este incremento prepara la preferencia P0. La administración/versionado de catálogos y parámetros sigue perteneciendo a BL-MVP-036 y las pantallas educativas posteriores consumen la revisión confirmada sin reescribir contenido canónico.
