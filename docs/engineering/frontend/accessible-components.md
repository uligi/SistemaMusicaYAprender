# Componentes accesibles esenciales · BL-MVP-019

BL-MVP-019 implementa la primera capa reutilizable de componentes accesibles del cliente web. Su
dependencia directa es BL-MVP-018, por lo que todos los componentes consumen los tokens visuales v1 en
lugar de introducir colores, espaciados, radios, elevaciones o movimiento aislados.

## Contrato de la línea base

La trazabilidad de BL-MVP-019 es `UI; ACC; DI-MVP-01-14`. La implementación aplica semántica HTML
nativa antes de ARIA, mantiene un orden de teclado natural, conserva foco visible y evita convertir
color en la única señal de estado.

Los componentes incluidos son:

- `Button`: botón nativo, tipo seguro por defecto, variantes primaria, secundaria y de riesgo.
- `Link`: enlace nativo con destino real y foco visible.
- `Field`: etiqueta persistente, ayuda enlazada, `aria-invalid` y error textual.
- `SelectField`: select nativo con el mismo contrato de etiqueta, ayuda y error.
- `Dialog`: elemento `dialog` modal nativo; Escape queda a cargo de la plataforma y `onClose` devuelve
  el foco al disparador.
- `DataTable`: tabla, caption y encabezados semánticos; en 320 px se refluye en filas etiquetadas sin
  exigir scroll horizontal de página.
- `Tabs`: patrón tablist/tab/tabpanel con foco móvil mediante Flecha izquierda/derecha, Inicio y Fin.
- `Alert`: texto redundante al color y región viva apropiada.
- `StateMessage`: contrato uniforme para UI-EST-01 a UI-EST-12.

## DI-MVP-01 a DI-MVP-14

DI-MVP-01 se aplica mediante elementos semánticos. DI-MVP-02 evita cambios de geometría inesperados
en los componentes base. DI-MVP-03 exige teclado, foco visible, cero trampas y retorno del foco del
diálogo. DI-MVP-04 usa texto además del color. DI-MVP-05 enlaza errores con su campo y explica la
corrección. DI-MVP-06 y DI-MVP-07 quedan como límites: un componente nunca concede permisos ni cambia
privacidad. DI-MVP-08 conserva la interfaz en español y usa `lang="ja"` para japonés. DI-MVP-09 hereda
los tokens de movimiento reducido. DI-MVP-10 aplica el objetivo táctil de 44 px. DI-MVP-11 no acopla
los componentes a YouTube. DI-MVP-12 mantiene composición fluida. DI-MVP-13 conserva la pila de Noto
Sans JP definida por tokens. DI-MVP-14 exige zoom/reflujo y base usable desde 320 px.

## Estados UI-EST-01 a UI-EST-12

El contrato incluye carga inicial, carga progresiva, sin resultados, vacío autorizado, YouTube no
disponible, red interrumpida, sesión vencida, acceso denegado, validación, conflicto de versión,
guardando y confirmado. `StateMessage` usa una región viva cortés y `aria-busy` únicamente cuando el
estado representa trabajo en curso.

## Fixture de regresión después de BL-MVP-020

BL-MVP-020 convierte `App.tsx` en el app shell real. Para que la regresión de BL-MVP-019 no dependa de
una pantalla temporal, los usos representativos de botón, enlace, campo, select, diálogo, tabla,
pestañas, alertas y UI-EST-01 a UI-EST-12 viven en
`apps/web/src/components/ui/AccessibilityContractFixture.tsx`.

El fixture compila con la aplicación y el verificador lo inspecciona, pero no agrega una ruta de
producto fuera de UI-MVP-001-032.

## Validación manual antes del commit

1. Recorrer la vista con Tab y Shift+Tab; ningún elemento interactivo debe perder foco visible.
2. Abrir un diálogo, cerrarlo con Escape y comprobar retorno del foco.
3. Usar Flecha izquierda/derecha, Inicio y Fin en pestañas.
4. Revisar formularios con etiqueta, ayuda y errores asociados.
5. Reducir el viewport a 320 px y confirmar reflujo sin scroll horizontal de página.
6. Verificar japonés con `lang="ja"` y sin glifos corruptos.

BL-MVP-022 añadirá Playwright, axe y capturas automatizadas.
