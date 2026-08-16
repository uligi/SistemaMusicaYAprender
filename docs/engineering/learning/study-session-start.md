# Inicio de sesión de estudio · BL-MVP-072

## Frontera transaccional

El inicio de estudio se ejecuta con `IRlsTransactionExecutor`, por lo que la conexión usa la identidad normal de aplicación y aplica `security.current_account_id()` antes de leer o escribir datos privados.

No se usa el pool backoffice.

## Elegibilidad

La clave del slug solo localiza el `recording_id`. La autorización real se vuelve a comprobar contra tablas canónicas:

1. `editorial.publication` activa y vigente;
2. `editorial.editorial_package` aprobado y congelado;
3. `editorial.publication_availability` pública, vigente y compatible con territorio/idioma;
4. `editorial.published_package_projection` existente como read model reconstruible, sin conceder autorización por sí misma;
5. `editorial.publication_component` y `editorial.package_component` con componente `EXERCISE` y checksum coincidente;
6. `learning.exercise_revision` / `exercise_definition` pertenecientes a la grabación publicada;
7. línea fuente, cuando existe, compatible con la revisión de letra del paquete.

Un borrador que no forme parte de una publicación no es elegible.

## Privacidad

`learning.study_session` queda vinculada a `learning.learner_profile`; ambas tablas están protegidas por RLS de propietario. Las respuestas y notas no forman parte del contrato de lectura ni de escritura de BL072.

La respuesta HTTP devuelve únicamente metadatos operativos de la sesión: identificador privado, estado, fecha, versión y número de publicación.

## Idempotencia

`Idempotency-Key` es obligatorio. Dentro de la misma transacción se toma un advisory lock por cuenta y se consulta `ops.idempotency_record`.

- mismo key + mismo digest: se devuelve la sesión ya confirmada;
- otro key por doble activación: se reutiliza la sesión activa de esa misma publicación;
- mismo key + solicitud diferente: `409`;
- key expirado: el registro técnico puede renovarse.

## Siguiente frontera

BL-MVP-073 creará la primera `exercise_instance` congelada y reanudable. BL072 no adelanta opciones, solución, respuesta, evaluación, evidencia ni progreso.
