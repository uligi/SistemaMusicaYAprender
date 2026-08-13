# BL-MVP-054 · Editor estructurado de letra japonesa

Materializa el editor de UI-MVP-021 sobre el modelo de BL053.

El editor permite agregar, quitar y reordenar secciones y líneas, asignar una etiqueta de voz/intérprete y
previsualizar el borrador antes de guardarlo. No publica contenido y no implementa todavía la segmentación manual
de tokens de BL055.

El contenido que no puede transcribirse sin inventar se representa con marcadores editoriales reservados:
`[UNKNOWN:INAUDIBLE]`, `[UNKNOWN:UNKNOWN]`, `[UNKNOWN:OMITTED]` y
`[UNKNOWN:PENDING_TRANSCRIPTION]`. El usuario ve etiquetas localizadas; el servidor valida el conjunto reservado
y rechaza variantes arbitrarias.

La lectura de la revisión entrega ETag. El guardado exige `If-Match`; si otra sesión crea una revisión más reciente,
se devuelve 412 y la interfaz conserva el borrador local para compararlo antes de adoptar o rebasar la versión del
servidor.
