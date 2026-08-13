# BL-MVP-061 — modelo de traducción, revisiones y alineaciones

## Alcance

BL-MVP-061 materializa el modelo editorial de M04 sobre las tablas físicas ya presentes en PostgreSQL. No añade migraciones ni duplica la letra japonesa.

La unidad de compatibilidad es una `content.lyrics_revision` exacta. Una traducción de una revisión japonesa anterior puede conservarse históricamente, pero no se declara compatible de forma automática con la revisión vigente.

## Modelo reutilizado

- `content.translation_revision`: revisión por letra exacta, idioma objetivo, tipo y número.
- `content.translation_line`: texto traducido con variantes independientes como `LITERAL` y `NATURAL`.
- `content.token_alignment`: relación explícita entre una unidad traducida y tokens japoneses. El grafo admite N:M.
- `content.translation_note`: notas editoriales separadas del texto traducido.
- `catalog.source_reference` + `editorial.provenance_record`: procedencia identificable de la revisión.

El español (`es`) es el idioma inicial del MVP, pero `target_language` conserva el modelo multilingüe y acepta etiquetas normalizadas sin columnas por idioma.

## Compatibilidad y cobertura

`TranslationRevisionAdministrationService` resuelve primero la revisión japonesa más reciente de la grabación y después busca una traducción cuya `lyrics_revision_id` coincida exactamente. Las líneas traducidas, la línea ancla de cada alineación, los tokens alineados y las notas ancladas se vuelven a limitar a esa misma `lyrics_revision_id` al construir el read model; una referencia cruzada válida para una FK individual no se mezcla en UI-MVP-023.

Si solo existen traducciones de revisiones japonesas anteriores:

- `hasStaleRevision=true`;
- no se selecciona una traducción incompatible;
- UI-MVP-023 explica que las alineaciones requieren revisión explícita.

La cobertura literal y natural se calcula por separado. Una revisión solo se marca `completeForReview` cuando cada línea fuente tiene ambas variantes y las alineaciones leídas pertenecen a la revisión japonesa actual.

## Alineación N:M

La relación N:M se representa con el grafo de `token_alignment`:

- una unidad traducida puede relacionarse con varios tokens;
- un token puede participar en varias unidades traducidas;
- `translation_line.line_id` conserva una línea ancla para orden y contexto;
- los tokens siguen siendo los objetos canónicos de M03.

BL-MVP-061 no duplica marcas temporales. La traducción consumirá la sincronización japonesa mediante estas relaciones en los BL posteriores.

## UI-MVP-023

La pantalla `/editorial/canciones/{id}/traduccion` deja de ser placeholder y presenta una vista estructural de solo lectura:

- revisión japonesa exacta;
- idioma y tipo;
- cobertura literal y natural;
- unidades españolas junto a japonés;
- alineaciones con tokens;
- notas y procedencia;
- estado explícito cuando la letra fuente cambió.

El editor de escritura pertenece a BL-MVP-062. BL-MVP-061 no publica, no somete a revisión y no expone comentarios internos a estudiantes.

## Dependencias externas

No se usa API de traducción, transcripción, diccionario ni analítica. El texto editorial permanece en el sistema propio. La única dependencia externa admitida por el MVP continúa siendo YouTube IFrame Player en los flujos que realmente reproducen video.
