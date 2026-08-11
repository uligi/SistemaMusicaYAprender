# BL-MVP-031K — renovar CSRF autenticado y consolidar `Instrucciones/`

## Primera falla observada

La puerta completa ya pasó:

- análisis, formato y build;
- `17/17` Playwright;
- `26/26` unit tests;
- arquitectura;
- arranque y salud de los siete servicios;
- regresión BL-MVP-030.

El primer RED actual ocurre en el smoke real de BL-MVP-031:

```text
grant autorizado esperaba '201' y obtuvo '400'
```

## Causa corregida

El smoke obtenía el token CSRF **antes** del login y reutilizaba ese mismo request token después de
autenticarse.

El endpoint `/api/v1/auth/csrf` usa `GetAndStoreTokens`, y la UI real obtiene un token fresco antes
de cada mutación. BL-MVP-031K hace lo mismo en el smoke: después del login renueva el CSRF usando la
cookie de sesión y vuelve a renovarlo antes de grant, retry, overlap, revoke, retry-revoke y
self-grant.

Además, si el grant vuelve a responder con un código inesperado, el smoke imprime el cuerpo
`application/problem+json` antes de fallar para que el siguiente diagnóstico tenga el `code` real.

## Reejecución segura

El target sintético ya no usa un `email_lookup_hash` constante. Ahora genera material aleatorio por
ejecución para que un smoke fallido no provoque una colisión artificial en la siguiente corrida.

## Organización documental

Por decisión del proyecto, todos los archivos `INSTRUCCIONES_*.md` se normalizan bajo:

```text
Instrucciones/
```

El instalador:

- mueve desde la raíz cualquier `INSTRUCCIONES_*.md` que todavía quede allí;
- si ya existe el destino, solo elimina el duplicado de raíz cuando ambos contenidos tienen el mismo
  SHA-256;
- falla si encuentra contenidos diferentes;
- actualiza el inventario de BL-MVP-031 para reconocer la reorganización.

Los README permanecen en `README/` y los instaladores en `scripts/`.
