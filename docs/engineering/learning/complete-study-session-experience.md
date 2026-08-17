# BL-MVP-078 · Experiencia completa y reanudable de sesión

## Decisión

BL-MVP-078 integra UI-MVP-011/012/013 con los hechos autoritativos de BL-MVP-072 a BL-MVP-077 y añade el ciclo de vida explícito requerido por CU-MVP-09. La continuidad no depende de `localStorage` ni `sessionStorage`.

## Dos estados diferentes

El producto muestra dos dimensiones que no se deben mezclar:

| Dimensión                | Estados                         | Fuente autoritativa                |
| ------------------------ | ------------------------------- | ---------------------------------- |
| Ciclo de vida de sesión  | `ACTIVE`, `PAUSED`, `COMPLETED` | `learning.study_session`           |
| Estado educativo visible | Pendiente, Guardado, Confirmado | submission, evaluación y evidencia |

**Pendiente** significa que todavía no existe una submission confirmada. **Guardado** significa que la submission ya existe pero la evaluación o evidencia puede seguir pendiente. **Confirmado** exige evaluación reproducible y evidencia confirmada.

## Pausar, continuar y finalizar

1. Una sesión inicia `ACTIVE`.
2. **Salir y continuar después** confirma `ACTIVE → PAUSED` antes de navegar al inicio.
3. El inicio privado muestra la sesión `PAUSED`; **Continuar sesión** confirma `PAUSED → ACTIVE` y después recupera la misma primera instancia congelada.
4. **Finalizar sesión** confirma `ACTIVE|PAUSED → COMPLETED`, fija `ended_at`, deja de aceptar hechos educativos nuevos y muestra un resumen coherente sin perder los hechos ya confirmados.
5. Cada transición requiere CSRF e `If-Match` con la versión observada. El trigger `ops.bump_version()` incrementa la versión al actualizar.

Una sesión pausada puede leerse y sus hechos históricos pueden recuperarse, pero el servidor no permite crear una nueva instancia, submission, evaluación o evidencia hasta que vuelva a `ACTIVE`. Una sesión completada tampoco acepta nuevas mutaciones educativas.

## Reintentos e idempotencia

Las barreras de pausa/finalización se aplican **antes de crear** nuevos hechos. Si la submission, evaluación o evidencia ya existe, su recuperación/reintento sigue reutilizando el registro lógico existente. Esto preserva BL-MVP-074/075/077.

## Concurrencia

Las transiciones de sesión toman un advisory lock por cuenta y sesión, bloquean la fila de `study_session` durante la transición y verifican la versión esperada. Las mutaciones educativas nuevas también bloquean esa fila al comprobar `ACTIVE`, de modo que pausa/finalización y una escritura educativa concurrente quedan serializadas. Una versión obsoleta devuelve `412 Precondition Failed`; no se hace last-write-wins silencioso.

## Accesibilidad CA-MVP-053

Las acciones **Empezar a practicar**, **Salir y continuar después / Pausar**, **Continuar sesión** y **Finalizar sesión** son controles de teclado. No existe temporizador obligatorio. El E2E focal recorre pausa → continuación → finalización por teclado y conserva cobertura Axe/320 px.

## Compatibilidad

- CSRF e idempotencia de BL072/074 se mantienen.
- Instancia congelada de BL073 se reutiliza.
- Evaluación reproducible de BL075 y feedback textual BL076 se conservan.
- Evidencia append-only BL077 se conserva.
- No hay escrituras `progress.*`, migraciones, publicación BL079 ni `resume_point` BL086.
