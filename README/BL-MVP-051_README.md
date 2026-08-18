# BL-MVP-051 — Corregir, retirar, restaurar o revertir publicación

## Alcance

F2 · EP-06 · 13 SP
Traza: CU-MVP-22 · UI-MVP-028 · CE-02-05, CE-09, CE-10, CE-14.
Dependencia: BL-MVP-050.

Resultado vinculante:

> Cada acción crea nueva revisión/acción trazable; historial y evidencia previa se conservan y el público ve el estado seguro.

## Inmutabilidad

BL051 no borra publicaciones, componentes, acciones ni casos de corrección.

- `WITHDRAW` cierra la publicación ACTIVE y la deja `WITHDRAWN`.
- `RESTORE` crea una **nueva publicación** desde una publicación histórica revalidada.
- `REVERT` vuelve efectiva una publicación histórica mediante una **nueva publicación**, sin borrar versiones posteriores.
- `SUBSTITUTE` activa un paquete corregido que ya pasó revisión y está `APPROVED`.

Cambiar directamente una fuente de otra grabación no es un atajo válido: una sustitución usa un paquete aprobado de la **misma grabación**, por lo que sincronización y componentes vuelven a pasar por la cadena editorial.

## Trazabilidad

Cada operación confirma conjuntamente `correction_case`, `publication_action`, auditoría primaria y outbox. `If-Match` + advisory lock detectan correcciones concurrentes y evitan last-write-wins.

## UI-MVP-028

Ruta: `/administracion/correcciones/{id}`.

Muestra publicación efectiva, acción/motivo, objetivo histórico o paquete aprobado, doble confirmación, historial inmutable y acciones trazables.

## Degradación de YouTube

BL051 no borra contenido propio cuando la fuente deja de ser embebible. La degradación del reproductor sigue el contrato ya implementado por BL058/BL063.

## Verificación focal

```powershell
& "C:\Program Files\Git\bin\bash.exe" `
  scripts/ci/editorial/verify-publication-correction.sh

npm.cmd run test:e2e -- editorial-correction.spec.ts
```
