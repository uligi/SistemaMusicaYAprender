# Cierre de sesión y revocación de sesión — BL-MVP-027

## Contrato

`POST /api/v1/auth/logout`:

- requiere sesión autenticada;
- requiere antiforgery de mismo origen;
- revoca en servidor solamente la sesión presentada;
- retira la cookie `__Host-MusicaAprender.Session`;
- responde sin identificadores de cuenta, sesión o token;
- utiliza `Cache-Control: no-store`;
- reutilizar la cookie revocada no autentica;
- una sesión concurrente independiente continúa válida.

La persistencia reutiliza `SecuritySessionTicketStore.RemoveAsync` y
`SecuritySessionPersistence.RevokeAsync`, por lo que BL-MVP-027 no cambia el esquema físico.

## UI-MVP-007

La acción `Cerrar sesión` aparece únicamente cuando la sesión está confirmada. El flujo es operable
con teclado, conserva foco visible y no persiste identificadores en URL, localStorage ni
sessionStorage.

## Trazabilidad

- BL-MVP-027
- CU-MVP-03
- UI-MVP-007
- CE-01
- CA-MVP-016
- CA-MVP-017
