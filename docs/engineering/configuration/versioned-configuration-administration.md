# Administración versionada de configuración — BL-MVP-036

## Propiedad y autorización

M19 conserva el gobierno técnico de `configuration.*`; el significado de cada catálogo o parámetro sigue perteneciendo a `owner_module`. M18 conserva autenticación, permisos y auditoría.

`/api/v1/administration/configuration` y sus operaciones usan la identidad backoffice separada. La ruta visible no autoriza ningún acceso. M19 entrega un `ConfigurationAuditIntent`; el adaptador de seguridad del API lo escribe mediante `PrimaryAuditWriter` dentro de la misma transacción, de modo que Configuration no consulta ni modifica directamente tablas de M18.

- lectura y simulación: `CONFIG.MANAGE` + assurance privilegiado reciente;
- activación: `CONFIG.MANAGE` + `CONFIG.APPROVE` + assurance privilegiado reciente;
- POST: antiforgery obligatorio;
- autorización: recalculada siempre en servidor.

## Ciclo de cambio

1. La UI obtiene la versión efectiva y el token de concurrencia.
2. El administrador informa valor, vigencia, motivo e impacto/dependencias.
3. La simulación valida propietario, formato, tipo/esquema, ámbito, vigencia, concurrencia y campos incompatibles con secretos.
4. La activación repite las validaciones dentro de una transacción.
5. La versión anterior recibe fin de vigencia; su contenido no se sobrescribe ni se borra.
6. Se inserta la nueva versión o entrada y se actualiza la proyección efectiva cuando corresponde.
7. Cambio, activación y auditoría se escriben en la misma transacción.
8. Un fallo revierte la transacción completa y deja efectivo el último estado confirmado.

## Concurrencia e idempotencia

La definición del parámetro o catálogo se bloquea durante la activación para serializar cambios del mismo objeto.

- parámetro: el cliente confirma `expectedVersionNo`;
- catálogo: confirma `expectedEntryId` + `expectedVersion`;
- si el estado cambió, la activación devuelve conflicto y obliga a recargar/simular;
- si un reintento encuentra exactamente el valor y vigencia ya efectivos, devuelve `alreadyApplied=true` sin crear otra versión.

Las restricciones físicas de vigencia continúan siendo la última barrera contra intervalos incompatibles.

## Secretos

M19 no es un secret store. Se rechazan claves de parámetro y propiedades JSON con nombres inequívocos de credenciales o secretos. La API no repite el valor rechazado en `ProblemDetails` ni lo escribe en auditoría.

Los secretos reales continúan bajo M18 y el almacén externo configurado.

## Evidencia histórica

`security.audit_event` conserva digest antes/después, motivo, impacto, actor, función autorizada, acción, objeto, momento y correlación. `configuration_change_set`, `configuration_change_item` y `configuration_activation` conservan la ejecución coordinada.

La reconstrucción histórica usa la identidad y vigencia de cada `parameter_version` o `catalog_entry`; nunca depende de reescribir el contenido anterior.
