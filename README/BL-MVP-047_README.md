# BL-MVP-047 — Ensamblar paquete educativo compatible

## Resultado

El espacio `UI-MVP-026` permite fijar revisiones exactas de letra, tiempos, traducción, análisis y ejercicios. El servidor valida que todas dependan de la misma revisión japonesa y persiste únicamente un `editorial_package` en estado `DRAFT` con `package_component` tipados y checksum SHA-256 determinista.

## Invariantes

- No existe fallback a “la última revisión”.
- El paquete DRAFT es mutable únicamente mientras `status_code = DRAFT` y `frozen_at IS NULL`.
- `If-Match` y la `version` monotónica evitan last-write-wins silencioso.
- La grabación debe conservar derechos vigentes antes de quedar `ReadyForFreeze`.
- Guardar BL047 no crea `review_submission`, `review_decision`, `publication` ni `publication_component`.
- BL-MVP-048 conserva la responsabilidad de congelar/someter; BL049 revisa y BL050 publica.

## Trazabilidad

- CU-MVP-20
- UI-MVP-026
- CE-03, CE-04, CE-05, CE-06, CE-09, CE-10
- Dependencias coordinadas: BL046, BL069, BL079

El ciclo normativo BL047 ↔ BL079 se resuelve como paquete técnico coordinado sin fusionar sus criterios de aceptación.
