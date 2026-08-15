# Previsualización editorial de karaoke

La pantalla `UI-MVP-022` de sincronización ofrece dos paneles de trabajo:

1. **Revisión de sincronización**: conserva el editor temporal existente.
2. **Previsualización de Karaoke**: reproduce la fuente de YouTube y renderiza el mismo componente
   `EducationalKaraoke` utilizado por el estudiante.

## Contrato DRAFT

La previsualización usa:

- la última revisión editorial de letra;
- la última sincronización compatible de la fuente elegida;
- la última traducción humana compatible con esa revisión de letra;
- el último análisis lingüístico compatible con esa misma revisión.

El endpoint es:

`GET /api/v1/editorial/song-drafts/{recordingId}/karaoke-preview?sourceId={sourceId}&language=es`

Requiere `EDITORIAL.DRAFT`.

No consulta `editorial.publication`, no requiere paquete publicado, slug público, territorio ni
disponibilidad pública.

## Degradación

Si falta sincronización, la letra puede verse sin línea activa. Si falta traducción o análisis,
las capas no disponibles se deshabilitan sin inventar datos. La fuente de YouTube continúa usando
el adaptador aislado BL058 y el motor local BL059.

La pantalla muestra siempre `VISTA PREVIA EDITORIAL · NO PUBLICA`.
