# Panel de análisis contextual

BL-MVP-068 materializa la etapa **Comprensión** de F3 sin adelantar BL-MVP-069.

## Decisiones

- `UI-MVP-009` mantiene el reproductor montado mientras el usuario consulta un token.
- `UI-MVP-010` reutiliza el mismo panel como deep link.
- La referencia de ruta del token es opaca y no publica UUID internos.
- La consulta pública vuelve a resolver la publicación elegible y los componentes exactos `LYRICS` + `ANALYSIS`.
- Una revisión incompatible termina en estado seguro; nunca se toma “el análisis más reciente”.
- La superficie japonesa siempre proviene de M03.
- El significado contextual se presenta antes que información adicional.
- Las lecturas ambiguas permanecen explícitas.
- JLPT y grado escolar son orientativos.
- No se invoca diccionario, traductor, segmentador ni modelo externo.

## Degradación

Un token válido puede no tener todos los apartados. Vocabulario, morfología, kanji y gramática se omiten o marcan como no disponibles de forma independiente.

YouTube puede continuar reproduciéndose porque abrir/cerrar el panel no cambia la identidad del componente `SynchronizedYouTubePreview`.

BL-MVP-069 podrá consolidar después estas consultas dentro del read model integral del paquete publicado.
