# Asistente editorial de nueva canción

BL-MVP-045 convierte UI-MVP-018 en un flujo guiado sin duplicar la autoridad de los servicios de catálogo.

## Secuencia

- Paso 1: identidad estable de artista. Se reutiliza la búsqueda y advertencia de duplicados de BL037.
- Paso 2: obra, grabación y fuente. Se reutiliza el alta transaccional de BL038 y la confirmación de correspondencia
  exacta de YouTube.
- Paso 3: borrador guardado. La interfaz ofrece continuidad hacia el expediente y derechos/procedencia.

## Límites

El asistente no publica, no crea un paquete editorial y no congela revisiones. Tampoco accede a PostgreSQL desde el
cliente. Los endpoints existentes siguen validando capacidad, alcance, CSRF e idempotencia.

UI-MVP-018 conserva la ruta `/editorial/canciones/nueva`. UI-MVP-019 y BL046 continúan siendo el límite del
expediente completo.
