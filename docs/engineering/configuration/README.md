# Configuración externa y secret store — BL-MVP-009

La imagen es idéntica entre ambientes. La configuración no secreta y los secretos tienen ciclos separados.

## Contrato

La aplicación recibe datos no secretos mediante proveedores normales de configuración de .NET
y recibe secretos mediante archivos montados en un directorio externo, por defecto `/run/secrets`.

Los nombres del contrato se versionan en `config/secrets/manifest.json`.

## Local

Docker Compose usa `secrets:`. Los valores viven en `secrets/local/`, carpeta ignorada por Git
y también excluida del contexto de construcción Docker.

`scripts/local/ensure-local-secrets.ps1` crea secretos aleatorios si no existen.

## CI

El job ejecuta primero un escaneo del árbol rastreado. Después crea secretos efímeros únicamente
para validar la definición Compose. Esos archivos no se publican como evidencia ni forman parte del commit.

## Pruebas y producción

La plataforma elegida deberá montar los mismos nombres desde su secret store. No se requiere recompilar
la imagen para cambiar valores.

## M19

M19 conserva parámetros funcionales no secretos. Un valor sensible no puede escribirse en M19.
El control físico asociado es DDC-27: cero secretos en M19.

## Rotación

`verify-secret-rotation.ps1` cambia las credenciales locales, sincroniza PostgreSQL, recrea únicamente
los consumidores y demuestra que:

1. los valores cambian;
2. las imágenes no se recompilan;
3. readiness vuelve a `Healthy`;
4. `docker inspect` no contiene los valores secretos.

Para un proveedor de producción, el mecanismo de rotación será el propio del secret store de la plataforma,
conservando este mismo contrato de nombres.
