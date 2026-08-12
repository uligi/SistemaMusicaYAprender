# Expediente editorial de canción

BL-MVP-046 materializa UI-MVP-019 como lectura compuesta y no como una segunda fuente de verdad.

## Componentes

El expediente consulta las identidades canónicas de catálogo y resume las revisiones ya existentes de:

- letra japonesa;
- sincronización;
- traducción;
- análisis lingüístico;
- banco de ejercicios;
- derechos y procedencia.

Una revisión ausente se informa como `NOT_STARTED / Sin revisión`. El expediente no crea componentes faltantes.

## Propiedad e incidencias

Cuando existe evidencia de actor se presenta de forma privada como `Tú` u `Otro responsable`; no se exponen
correos ni datos de perfil. Los hallazgos abiertos o reconocidos se leen de `ops.data_quality_issue` para la
grabación y los objetos de revisión que forman parte del expediente.

## Autorización

El endpoint requiere sesión autenticada, resuelve grants efectivos una vez y usa `AuthorizationScopeMatcher`
contra el `recording_id`. La lista de accesos navegables se deriva en el servidor. La navegación visible nunca
sustituye la autorización de los endpoints de cada componente.

## Frontera

BL046 es de lectura y coordinación. BL047 ensamblará el paquete compatible; BL048 lo congelará y someterá;
BL049 ejecutará revisión y BL050 publicará de forma atómica.
