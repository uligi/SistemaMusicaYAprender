# Bandeja editorial por capacidades

BL-MVP-044 materializa UI-MVP-017 como una lectura operativa del backoffice. Su fuente de verdad sigue siendo
el catálogo, los objetos editoriales, la auditoría y los grants efectivos; no se crea una segunda tabla de
"bandeja".

## Autoridad

El endpoint requiere una sesión autenticada. Después carga los grants vigentes una sola vez y aplica
`AuthorizationScopeMatcher` contra cada `recording_id`. Un registro sin al menos una capacidad aplicable no se
devuelve. Las acciones se generan en el servidor.

## Campos

- Estado: prioriza publicación, sumisión, paquete y finalmente grabación.
- Propietario: última cuenta auditada sobre la grabación, sin revelar identidad ajena.
- Bloqueo: `editorial.editorial_lock` vigente.
- Procedencia: vínculo entre crédito y `editorial.provenance_record`.
- Última actividad: auditoría o hitos editoriales disponibles.
- Siguiente acción: explicación del siguiente paso compatible con el estado y capacidad.
- Acciones: solo rutas existentes y autorizadas.

## Fronteras

No se crea `/editorial/canciones`. La bandeja permanece en `/editorial`. BL045-BL050 implementarán expediente,
paquete, congelación, revisión y publicación. La bandeja puede mostrar el siguiente paso sin ejecutar una
operación que todavía no pertenece a BL044.
