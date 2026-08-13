# Editor de línea de tiempo · BL-MVP-057

## Contrato

UI-MVP-022 reutiliza `content.timing_revision` y `content.timing_segment` de BL-MVP-056. No se crea migración.

Cada editor se abre para:

`recording_id + lyrics_revision_id + source_id`.

El POST existente acepta `expectedRevisionNo`. Un replay exacto del último checksum sigue siendo idempotente; si el contenido difiere y la revisión vigente ya no coincide con la base abierta por el editor, el servidor responde conflicto y no crea una revisión.

## Marcado

El cursor temporal del editor se expresa en milisegundos. `Marcar inicio` y `Marcar fin` copian el cursor al límite elegido. Los mismos valores siempre pueden modificarse con controles numéricos; ninguna acción esencial depende de arrastre.

La precisión `LINE` guarda un intervalo por línea. La precisión `TOKEN` exige tiempo para todos los tokens canónicos y conserva el orden de la revisión de letra.

## Desplazamiento múltiple

El usuario selecciona líneas y aplica un delta entero en milisegundos. El editor desplaza todos los límites de la selección y vuelve a ejecutar las validaciones antes de habilitar el guardado.

## Previsualización

BL-MVP-057 usa una previsualización temporal local: cursor, play/pausa local y línea activa. No carga el IFrame ni finge reproducción audiovisual. BL-MVP-058 será propietario del adaptador YouTube y BL-MVP-059 del motor de sincronización con eventos reales.

## Borrador parcial y conflictos

Las líneas sin temporizar se omiten del POST y la UI informa `X de N líneas`. Una revisión parcial nunca se presenta como completa.

Errores de validación y HTTP 409 conservan el borrador local. `expectedRevisionNo` impide sobrescritura silenciosa entre dos editores.
