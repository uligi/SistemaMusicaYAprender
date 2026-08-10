# BL-MVP-021D — Correcciones detectadas en revisión del diff staged

## Motivo

La revisión previa al commit encontró tres huecos de comportamiento que las pruebas anteriores no cubrían.

### 1. Invalidación de caché por prefijo

La clave de caché tenía esta forma:

```text
/api/v1/preferences::es-CR
```

pero `invalidate('/preferences')` construía:

```text
/api/v1/preferences::es-CR
```

y luego usaba `startsWith`.

Eso podía invalidar la ruta exacta del locale predeterminado, pero no una subruta como:

```text
/api/v1/preferences/details::en
```

y tampoco invalidaba variantes de otros idiomas. Era contrario a la intención explícita de “invalidar prefijos”.

La corrección separa el prefijo del locale y usa límites de recurso para invalidar:

- ruta exacta;
- query de la misma ruta;
- subrutas;
- todas las variantes de idioma;

sin invalidar siblings como `/preferences-other`.

### 2. Cancelación durante lectura del cuerpo

El cliente ya trataba correctamente un `AbortSignal` cancelado antes/durante `fetch`, pero si la cancelación ocurría mientras `response.json()` estaba leyendo el body, el `catch` de éxito lo convertía en `unexpected`.

La corrección conserva `cancelled` también en esa fase y comprueba cancelación después de normalizar un ProblemDetails.

### 3. Confinamiento real a `/api/v1`

`normalizePath` rechazaba URLs absolutas, pero aceptaba rutas como:

```text
/../health
/%2e%2e/health
```

El navegador puede normalizar esos segmentos y sacar la solicitud del prefijo `/api/v1`, aunque siga siendo same-origin.

La corrección resuelve la ruta contra un origen ficticio mediante `URL`, verifica el pathname canónico y rechaza cualquier ruta que no permanezca dentro de la base API configurada. También prohíbe fragmentos.

## Archivos modificados

- `apps/web/src/data/http/http-client.ts`
- `apps/web/src/data/http/read-cache.ts`
- `scripts/frontend/verify-http-client.mjs`
- `docs/engineering/frontend/http-data-client.md`

Además se agrega este README de corrección.

## Nuevas pruebas conductuales

El verificador agrega:

1. cancelación durante `response.json()`;
2. invalidación de `/preferences` que:
   - limpia `/preferences`;
   - limpia `/preferences/details`;
   - limpia variantes `es-CR` y `en`;
   - no limpia `/preferences-other`;
3. rechazo de `/../health`;
4. rechazo de `/%2e%2e/health`;
5. comprobación de que `fetch` no se ejecuta cuando una ruta intenta escapar de `/api/v1`.

## Preflight aislado

Se ejecutó:

```text
tsc strict sobre apps/web/src/data/http/*.ts
node --check scripts/frontend/verify-http-client.mjs
node scripts/frontend/verify-http-client.mjs
```

Resultado:

```text
OK: BL-MVP-021 cliente HTTP tipado verificado: cancelación, ETag, ProblemDetails, reintentos seguros y estados guardando/confirmado.
```

El repositorio del usuario con TypeScript 7.0.2 continúa siendo la autoridad final.
