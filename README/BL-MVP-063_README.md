# BL-MVP-063 — Capas japonés, furigana, romaji y español

## Trazabilidad

- CU-MVP-07
- UI-MVP-004, UI-MVP-009
- CE-04, CE-13
- Dependencias consumidas: BL-MVP-034, 060-062 y 065.

## Resultado

El reproductor permite activar u ocultar localmente:

- japonés;
- furigana;
- romaji;
- español.

Cambiar una capa solo modifica presentación React y no remonta ni reinicia el reproductor de YouTube.

## Revisión publicada exacta

`PublicSongLearningLayersService` revalida publicación, disponibilidad, fuente y componentes `LYRICS`, `TRANSLATION` y `ANALYSIS` realmente publicados. Traducción y análisis solo se leen cuando apuntan a la misma `lyrics_revision_id`.

El japonés conserva el texto de `lyric_line`; tokens y offsets se usan únicamente para insertar ayudas sin sustituir la superficie canónica.

## Presentación

- japonés declara `lang="ja"`;
- furigana usa `ruby`, `rt` y `rp`;
- romaji es una capa separada y reutiliza el resolver local de BL065;
- una lectura ambigua no se elige silenciosamente;
- español prefiere variante NATURAL y usa LITERAL como respaldo;
- ausencia de una capa se muestra como capacidad no disponible, no como contenido inventado.

## Exclusiones

No hay traducción, diccionario, segmentación o análisis externo. No persiste preferencias: BL081/082 aplicarán preferencias confirmadas y temporales sobre estos controles.
