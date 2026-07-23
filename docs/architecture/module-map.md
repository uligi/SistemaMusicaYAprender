# Mapa de módulos y propiedad

La solución sigue un monolito modular. Compartir proceso y base física no autoriza a un módulo a leer o escribir directamente la persistencia de otro.

| Componente | Propietario | Esquema | Puede depender de |
|---|---|---|---|
| Identity | M01 | `identity` | BuildingBlocks |
| Security | M18 | `security` | BuildingBlocks |
| Catalog | M02 | `catalog` | BuildingBlocks |
| Content | M03-M05 | `content` | BuildingBlocks |
| Learning | M06-M08 | `learning` | BuildingBlocks |
| Progress | M09 | `progress` | BuildingBlocks |
| Editorial | M15 | `editorial` | BuildingBlocks |
| Configuration | M19 | `configuration` | BuildingBlocks |
| API | Composición | — | todos los módulos y BuildingBlocks |
| Worker | Composición asíncrona | `ops` por contratos | BuildingBlocks y contratos autorizados |

## Ausencias intencionales

M10-M14, M16 y M17 no tienen proyectos vacíos en el MVP. Entrarán cuando una versión aprobada incorpore su funcionalidad.
