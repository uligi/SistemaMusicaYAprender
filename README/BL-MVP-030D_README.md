# BL-MVP-030D — completar aliases omitidos por destino canónico repetido

## Causa exacta

030C confirmó que todavía quedaban:

- `lyrics:edit`
- `timing:edit`
- `translation:edit`
- `translation:review`
- `analysis:edit`
- `analysis:review`
- `exercise:edit`

La primera puerta BL-MVP-030 había mostrado esos reemplazos como `ya estaba aplicado`.

El motivo es que `Replace-ExactText` consideraba una transformación aplicada si encontraba el
`NewText` **en cualquier parte del archivo**. Varios routes comparten como destino
`EDITORIAL.DRAFT` o `EDITORIAL.DRAFT + EDITORIAL.REVIEW`. Después de convertir el primer route, ese
destino ya existía y las transformaciones posteriores se saltaron aunque sus aliases legacy
continuaran presentes.

## Corrección

030D reemplaza los aliases restantes tomando como condición únicamente la presencia del texto
legacy. Que el destino canónico exista en otro route ya no puede cancelar la transformación.

La puerta base queda reconciliada con la misma regla para instalaciones/rejecuciones futuras y
formatea los archivos BL-MVP-030 antes del quality gate.

030D valida:

- ausencia de todos los aliases legacy;
- presencia de todos los `permission_code` canónicos requeridos;
- Prettier 3.9.6;
- TypeScript;
- restauración de `tsconfig.app.tsbuildinfo`;
- `git diff --check`.

No cambia el diseño del motor de autorización.
