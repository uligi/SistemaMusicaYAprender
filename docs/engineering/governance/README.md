# Gobierno de issues y Pull Requests

BL-MVP-005 convierte la línea base de planificación en controles de trabajo visibles en GitHub.

## Reglas

1. Cada PBI BL-MVP se registra como un issue separado y conserva el identificador en el título.
2. El issue usa el formulario `Implementación BL-MVP`; los issues en blanco están deshabilitados.
3. El issue exige fase, épica, tipo, trazabilidad, criterios, datos/permisos, estados/errores, pruebas,
   dependencias, riesgo de datos, riesgo de seguridad/privacidad, evidencia y DoD aplicable.
4. Las tareas internas permanecen como checklist salvo que tengan entrega, responsable o evidencia independiente.
5. Una dependencia bloqueante se enlaza con `Blocked by` / `Blocks`; no se duplica el contenido del issue dependiente.
6. Un issue se cierra por Definition of Done, no porque el código haya sido escrito.
7. Los documentos técnicos son la fuente normativa; GitHub registra la ejecución y la evidencia.

## Revisión de PR

El PR debe enlazar el issue y conservar la misma trazabilidad. La plantilla recuerda el requisito de revisión
independiente de RNF-MVP-140. La protección automática de ramas y el número de aprobaciones se configurarán
como control del repositorio cuando se habilite esa política; esta plantilla no sustituye esa protección.
