# BL-MVP-057 · Editor de línea de tiempo y sincronización

Implementa el editor funcional de UI-MVP-022 sobre el modelo temporal ya creado por BL-MVP-056.

El editor:

- trabaja sobre una revisión exacta de letra y una fuente exacta;
- permite marcar inicio y fin mediante un cursor temporal local;
- permite editar límites numéricamente sin depender de arrastre;
- permite temporización por línea o por todos los tokens canónicos de una línea;
- permite desplazar de forma controlada un conjunto seleccionado de líneas;
- ofrece una previsualización local del cursor y de la línea activa sin cargar el IFrame de YouTube;
- guarda borradores parciales sin presentarlos como sincronización completa;
- conserva el borrador ante errores y conflictos;
- envía `expectedRevisionNo` para evitar que una edición obsoleta sobrescriba silenciosamente una revisión posterior;
- reutiliza las validaciones de BL-MVP-056 para tiempos negativos, invertidos, fuera de duración, orden y solapamientos;
- no publica contenido.

BL-MVP-058 incorporará el adaptador aislado del YouTube IFrame y BL-MVP-059 el motor local de sincronización de reproducción. BL-MVP-057 no adelanta esas responsabilidades.
