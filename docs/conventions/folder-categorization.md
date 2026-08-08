# Convención de carpetas y categorización

El repositorio prioriza organización visible por categorías. Si varios archivos comparten una responsabilidad reconocible, se agrupan en una carpeta; si una carpeta empieza a mezclar responsabilidades, se subdivide.

## Regla de profundidad

Se usa `área -> subárea -> responsabilidad`, evitando carpetas de un solo archivo cuando no aporten significado. No se crean capas solo para aumentar profundidad.

## Backend

- `apps/api/Endpoints`: público, estudiante, editorial y administración.
- `apps/api/Middleware`: errores, seguridad y observabilidad.
- `src/Modules/<Módulo>`: `Domain`, `Application`, `Infrastructure`, `Contracts` y `Metadata`.
- Dentro de cada capa, las funcionalidades se agrupan por concepto de negocio antes que por tipo genérico de clase.

Ejemplo futuro:

```text
src/Modules/Catalog/Application/Songs/Create/
  CreateSongCommand.cs
  CreateSongHandler.cs
  CreateSongValidator.cs
```

## Frontend

`apps/web/src/features` se divide por capacidad: cuenta, catálogo, player, letra, análisis japonés, ejercicios y progreso. Los elementos reutilizables viven en `shared` y los estilos en subcategorías propias.

## Base de datos

`database/postgresql` queda separado en `bootstrap`, `schema`, `seeds`, `migrations`, `tests` y `master`; `schema` vuelve a dividirse por los nueve esquemas propietarios aprobados.

## Relación con los módulos

Los códigos M01-M09, M15, M18 y M19 se conservarán en documentación, namespaces conceptuales o subáreas cuando ayuden a la trazabilidad. Los módulos diferidos no reciben implementación vacía.
