# BL-MVP-044 · Bandeja editorial por capacidades

Implementa UI-MVP-017 en `/editorial` sin crear una ruta adicional `/editorial/canciones`.

La API construye candidatos editoriales desde catálogo y cadena editorial, resuelve una sola vez los grants
vigentes del actor y aplica el alcance por objeto para `EDITORIAL.DRAFT`, `EDITORIAL.REVIEW`,
`EDITORIAL.PUBLISH` y `EDITORIAL.CORRECT`.

La respuesta no expone correos ni identidades de otras cuentas. El propietario se presenta como `Tú`,
`Otro responsable` o `Sin responsable identificado`, usando auditoría como evidencia de actividad.

La bandeja muestra estado, propietario, bloqueo activo, procedencia, fuente, última actividad, siguiente
acción y exclusivamente enlaces autorizados. La visibilidad de frontend nunca sustituye la autorización del
servidor.

No implementa ensamblado, congelación, revisión ni publicación: BL045-BL050 conservan esas responsabilidades.
