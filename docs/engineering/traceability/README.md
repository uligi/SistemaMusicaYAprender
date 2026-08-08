# Convención de trazabilidad del MVP

La trazabilidad debe poder seguirse en ambas direcciones:

`requisito / CU / RNF -> BL-MVP -> issue -> PR -> commit -> pruebas / CI -> evidencia`

## Identificadores aceptados

- Backlog: `BL-MVP-001` a `BL-MVP-100`.
- Fase: `F0` a `F6`.
- Épica: `EP-00` a `EP-13`.
- Función: `CU-MVP-*`, `CA-MVP-*`, `UI-MVP-*`, `CE-*`, `RF-M*`, `RN-M*`.
- Calidad/diseño: `RNF-MVP-*`, `ARC-*`, `DDC-*`, `DI-MVP-*`.

## Regla para historias

Una historia debe declarar CU/CA/UI/CE aplicables y, cuando corresponda, los RF/RN exactos heredados
del caso de uso.

## Regla para habilitadores

Un habilitador debe declarar RNF/ARC/DDC/DI aplicables.

## Evidencia

La evidencia debe identificar como mínimo PR o commit, ejecución o reporte reproducible, ambiente, fecha y
responsable. La evidencia de aceptación debe corresponder al mismo commit/candidato que se pretende aceptar.
