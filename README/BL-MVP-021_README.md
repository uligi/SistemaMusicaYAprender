# BL-MVP-021 · Cliente HTTP tipado y ProblemDetails

## Resultado aceptable

> Cancelación, ETag, errores, reintentos seguros y estados guardando/confirmado se manejan de forma uniforme.

## Implementación

- `TypedHttpClient` sobre `fetch` nativo, sin dependencia npm adicional.
- Base REST same-origin `/api/v1` y `credentials: same-origin`.
- `AbortSignal` para cancelación.
- Caché GET breve en memoria + ETag / `If-None-Match` / `304`.
- `If-Match` para concurrencia optimista.
- `application/problem+json` normalizado por código estable y `correlation_id`.
- Errores recuperables alineados con DI-MVP-05 sin renderizar `title/detail` libres del servidor.
- JSON UTF-8 y `Accept-Language: es-CR`, sin transformar japonés, alineado con DI-MVP-08.
- Máximo tres intentos con backoff+jitter solo para lecturas seguras o escrituras con `Idempotency-Key`.
- Estado de mutación `UI-EST-11 Guardando` → `UI-EST-12 Confirmado`; validación/conflicto/sesión/red usan los estados ya definidos.
- Reverse proxy conserva `/api/v1/` para los contratos REST v1 y mantiene el proxy heredado `/api/` para probes existentes.

## No incluido

- No se crean endpoints funcionales de identidad, catálogo o estudio.
- No se agrega React Query, Axios, SWR ni otra librería HTTP.
- No se cambia SQL, migraciones, roles ni secretos.
- No se persisten respuestas, tokens o caché privada en almacenamiento local.
- BL-MVP-022 incorporará Playwright/axe/pruebas visuales; BL-MVP-023 será la primera pantalla funcional de registro.

## Verificación

```powershell
.\scripts\apply-bl-mvp-021.ps1
```

El apply ejecuta regresiones BL-MVP-018/019/020, el verificador conductual BL-MVP-021, TypeScript, build, Docker Compose y la puerta completa de calidad.
