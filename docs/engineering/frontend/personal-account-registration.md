# Registro de cuenta personal · BL-MVP-023

## Contrato de la pantalla

`UI-MVP-005` es pública y vive en `/registro`. Solicita solo el correo necesario para iniciar una cuenta pendiente. El formulario usa `type="email"`, `autocomplete="email"`, etiqueta visible, ayuda asociada, mensaje de error enlazado y botón nativo.

La pantalla no solicita contraseña, términos ni token porque esas capacidades pertenecen a BL-MVP-028, BL-MVP-024 y BL-MVP-025. Tampoco presenta un enlace como confirmación de existencia: una cuenta nueva y un correo ya conocido reciben exactamente el mismo estado `UI-EST-12`.

## Reintento seguro

El cliente genera una `Idempotency-Key` por operación lógica. Los reintentos automáticos y manuales tras una falla conservan la clave mientras el correo no cambie. Una confirmación limpia la operación; un envío posterior inicia otra clave y el servidor sigue evitando duplicados por el HMAC único del correo.

El correo no se escribe en almacenamiento web persistente. Ante validación o falla de red permanece únicamente en el estado de React para que la persona pueda corregir o reintentar sin volver a escribirlo.

## Estados

- `UI-EST-09`: dirección inválida o rechazada; foco en el campo y valor preservado.
- `UI-EST-11`: solicitud en curso; botón deshabilitado y operación idempotente estable.
- `UI-EST-12`: respuesta genérica recibida; el campo se limpia.
- `UI-EST-06`: falla temporal o de red; datos preservados y reintento seguro.

## Comprobación

La batería Playwright intercepta el contrato same-origin `/api/v1/auth/register` para validar la interfaz sin datos manuales. El verificador CI de identidad levanta el API real contra PostgreSQL y comprueba la transacción, el resultado no enumerativo y la protección del correo.
