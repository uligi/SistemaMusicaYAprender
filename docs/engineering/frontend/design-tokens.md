# Tokens visuales v1 · BL-MVP-018

`apps/web/src/styles/tokens/v1.css` es la fuente versionada de los tokens visuales del MVP. El archivo
`apps/web/src/styles/index.css` consume estos tokens y no debe volver a introducir colores hexadecimales
aislados ni valores de tipografía, espaciado, radio, elevación o movimiento que correspondan al sistema
visual.

## Contrato de color

La paleta es provisional; los **roles semánticos** son vinculantes.

| Token                | Valor     | Uso                        |
| -------------------- | --------- | -------------------------- |
| `--ma-color-ink`     | `#182338` | Texto principal            |
| `--ma-color-muted`   | `#5B6475` | Texto secundario           |
| `--ma-color-primary` | `#2F4EB2` | Acción y selección         |
| `--ma-color-success` | `#107C66` | Confirmación               |
| `--ma-color-warning` | `#9A5B00` | Revisión o atención        |
| `--ma-color-danger`  | `#B83A3A` | Error o acción riesgosa    |
| `--ma-color-surface` | `#F7F8FC` | Fondo secundario           |
| `--ma-color-border`  | `#D9DEEA` | División estructural       |
| `--ma-color-canvas`  | `#FFFFFF` | Superficie principal clara |

Un estado nunca debe depender únicamente del color. Los pares de texto/estado deberán conservar la
redundancia textual e icónica definida por DI-MVP-04.

## Tipografía

La interfaz usa una pila que comienza en `Noto Sans`. El contenido japonés usa una pila que comienza en
`Noto Sans JP` y debe conservar `lang="ja"` en el HTML. La base de interfaz es 16 px; la información
secundaria no baja de 14 px. El japonés comienza en 18 px y los títulos de página usan el intervalo
28–36 px. Los datos/tiempos utilizan cifras tabulares.

BL-MVP-018 define la pila y sus tokens, pero no introduce una descarga de tipografía de terceros en
runtime. El producto sigue sin depender de APIs externas para presentar su contenido.

## Espaciado, radios y objetivo táctil

Escala vinculante de espaciado: **4, 8, 12, 16, 24, 32, 48 y 64 px**.

Radios vinculantes:

- control: 10 px;
- panel: 14 px;
- superficie principal: 18 px.

El token de objetivo táctil es 44 px.

## Elevación

La elevación es excepcional. `--ma-elevation-none` es el estado ordinario y
`--ma-elevation-floating` queda reservado para paneles flotantes, diálogos y menús. Los contenedores
ordinarios se separan mediante espacio y borde.

## Movimiento

Las duraciones y curva de movimiento se consumen desde tokens. En
`prefers-reduced-motion: reduce`, toda duración no esencial se reduce a `0ms` y la distancia de
movimiento a cero. No se introducen destellos.

## Versionado

La ruta `tokens/v1.css` y `--ma-design-token-version: 1` fijan la versión. Un cambio incompatible de
nombres o significado semántico requiere una versión nueva; una corrección compatible puede mantener
v1 y debe quedar documentada en el mismo commit.

## Verificación

Ejecutar:

```powershell
node .\scripts\frontend\verify-design-tokens.mjs
```

El verificador confirma los valores vinculantes, la escala, el tratamiento de movimiento reducido, la
importación de v1, el uso real de todas las familias de tokens y la ausencia de colores crudos en
`index.css`.

## Codificación y esquema de color

El documento HTML declara `UTF-8`, y los textos de interfaz con español/japonés deben conservarse como
UTF-8 extremo a extremo. El apply de BL-MVP-018 escribe los archivos generados mediante bytes UTF-8
decodificados desde Base64 para no depender de la interpretación de literales no ASCII de Windows
PowerShell 5.1.

La línea base v1 usa superficies claras y declara `color-scheme: only light`; el tema oscuro no forma
parte de BL-MVP-018. Un tema alternativo deberá introducirse explícitamente mediante tokens y pruebas, no
mediante transformación automática del navegador.
