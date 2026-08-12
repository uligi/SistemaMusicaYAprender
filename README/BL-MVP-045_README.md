# BL-MVP-045 · Asistente de nueva canción

Implementa la experiencia integrada de UI-MVP-018 en `/editorial/canciones/nueva`.

El asistente no crea una segunda lógica de catálogo. Orquesta los contratos ya publicados por BL037 y BL038:

1. buscar o crear una identidad estable de artista;
2. registrar obra, grabación y referencia exacta de YouTube;
3. confirmar un borrador y continuar al expediente o a derechos/procedencia.

La creación conserva las verificaciones existentes de duplicados, CSRF, idempotencia, alcance y fuente exacta. No
se añade SQL, migración, acceso directo a PostgreSQL ni una acción de publicación.

BL046 seguirá siendo responsable de convertir UI-MVP-019 en el expediente editorial completo.
