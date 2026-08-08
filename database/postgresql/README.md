# PostgreSQL

Estructura reservada para la implementación física aprobada del MVP:

- `bootstrap`: roles y extensiones.
- `schema`: DDL separado por esquema propietario.
- `seeds`: datos semilla y catálogos iniciales.
- `migrations`: artefactos de migración/versionado.
- `tests`: validaciones SQL y consultas de prueba.
- `master`: ensamblado autónomo para instalaciones nuevas.

BL-MVP-003 solo crea la organización y las reglas de formato. El DDL entra en los PBI de datos correspondientes.
