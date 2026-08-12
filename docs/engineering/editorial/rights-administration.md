# BL-MVP-040 — derechos, usos, territorios y vigencias

## Alcance

UI-MVP-020 incorpora el expediente de derechos de M15 sobre una grabación editorial. El cambio
reutiliza `editorial.rights_holder`, `editorial.rights_record`, `editorial.rights_scope` y
`ops.stored_object`; no agrega migración.

## Reglas

- El titular declarado no se confunde con una verificación concluida.
- La base de autorización, el uso, el canal, el territorio y la vigencia quedan explícitos.
- El territorio es obligatorio por alcance: su ausencia nunca se interpreta como autorización mundial.
- La evidencia se cifra mediante el `IObjectStore` privado y PostgreSQL conserva solamente su descriptor.
- El pool backoffice no recibe INSERT directo sobre `ops.stored_object`; registra metadata solo mediante `ops.register_rights_evidence_object`, fijada a M15/RIGHTS_EVIDENCE.
- La lectura de derechos no devuelve `storage_key`, bytes ni claves de cifrado.
- La disponibilidad se revalida con coincidencia territorial exacta; una preferencia del usuario no amplía el derecho.
- Una autorización vencida, sustituida o sin procedencia suficiente no vuelve elegible la publicación.
- Una corrección crea un nuevo `rights_record`; el anterior queda `SUPERSEDED`, no se elimina.
- Idempotencia: misma clave y mismo contenido devuelve replay; misma clave con contenido distinto devuelve conflicto.
- La creación y sustitución se auditan con actor, motivo, correlación, `before_digest` y `after_digest`.
- La escritura exige `EDITORIAL.DRAFT`; lectura/evaluación permiten `EDITORIAL.DRAFT` o `EDITORIAL.REVIEW`, siempre revalidados en servidor con ámbito M15/recording.

## Límite

BL-MVP-040 calcula elegibilidad de derechos del borrador. No publica contenido. La proyección pública y la revalidación pública se implementan en BL-MVP-041 y los flujos posteriores de publicación.
