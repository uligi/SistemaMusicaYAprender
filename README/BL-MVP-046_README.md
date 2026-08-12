# BL-MVP-046 · Expediente editorial de canción

Implementa UI-MVP-019 en `/editorial/canciones/{id}` como una vista agregada de lectura.

El expediente reúne catálogo, letra, sincronización, traducción, análisis, ejercicios y derechos. Cada componente
muestra la última revisión disponible, estado y un propietario seguro (`Tú`, `Otro responsable` o
`Sin responsable identificado`). Las ausencias permanecen explícitas como `Sin revisión`.

La API vuelve a resolver grants efectivos y alcance por `recording_id` antes de devolver el expediente. También
resume procedencia/derechos, expone incidencias abiertas de `ops.data_quality_issue` vinculadas a los objetos
visibles y deriva en servidor la lista de accesos permitidos.

BL046 no congela, no somete y no publica. BL047-BL050 conservan paquete, congelación, revisión y publicación.
No agrega tablas ni migraciones.
