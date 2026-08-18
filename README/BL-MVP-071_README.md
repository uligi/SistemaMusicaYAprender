# BL-MVP-071 · Autoría de completar espacios con opciones

## Resultado aceptable

> El editor elige ancla, espacio, distractores y retroalimentación; validación impide opciones ambiguas o sin respuesta.

## Experiencia editorial

UI-MVP-025 incorpora un creador guiado en cuatro pasos:

1. elegir la línea exacta y tocar el token que se ocultará;
2. escribir entre 2 y 4 distractores;
3. definir competencia, explicación, retroalimentación y dificultad;
4. probar el ejercicio como **BORRADOR · NO PUBLICADO** antes de guardarlo.

La respuesta correcta se toma del token canónico seleccionado; no se escribe manualmente.

## Seguridad e integridad

- GET/POST protegidos con `EDITORIAL.DRAFT` y ámbito M08;
- POST exige CSRF + `If-Match`;
- fuente fijada a la revisión de letra DRAFT exacta;
- Unicode NFKC y espacios normalizados para detectar opciones duplicadas/ambiguas;
- `jp_backoffice` conserva SELECT sobre `learning`;
- las escrituras se encapsulan en `learning.save_fill_blank_exercise_draft(...)` con `SECURITY DEFINER`, `search_path` fijo, sin acceso PUBLIC y `EXECUTE` acotado;
- la vista previa no crea sesión, instancia, respuesta, evidencia ni progreso;
- no publica. La validación/publicación dentro del paquete corresponde a BL-MVP-079.

## Fix de integración posterior

FIX-MVP-EDITORIAL-CRUD-DESKTOP-001 añade edición/corrección desde el banco y registra procedencia
`EXERCISE_REVISION` al guardar, cerrando el hueco que impedía que ejercicios creados por BL071
superaran la validación de BL079.
