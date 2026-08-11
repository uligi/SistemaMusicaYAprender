# Preferencias personales P0

BL-MVP-034 mantiene la frontera de propiedad definida entre M01 y M18.

`security.account`, credenciales, sesiones y MFA continúan en M18. `identity.user_profile`, `identity.preference_set` y `identity.preference_revision` contienen únicamente experiencia de producto y decisiones personales permitidas.

La cabeza `preference_set` es única por cuenta. Cada cambio confirmado inserta una nueva `preference_revision` y mueve la cabeza dentro de la misma transacción. La versión de la cabeza funciona como concurrencia optimista. Un valor inválido o una versión obsoleta no crea revisión ni sustituye la configuración vigente.

El contrato P0 usa `LANGUAGE/ES` activo del catálogo M19 y guarda su versión en `provenance.languageCatalogVersion`. El servidor controla la procedencia; el cliente no puede enviar ni modificar ese dato.

Defaults seguros: interfaz y traducción en español, kanji+kana visibles, furigana adaptativo, romaji como ayuda, actividad privada, movimiento reducido y protección contra destellos. Accesibilidad no altera puntaje, progreso ni el contenido canónico.

RLS limita tanto la cabeza como su historial al `app.account_id` de la transacción. La API no acepta un `accountId` objetivo: `/api/v1/preferences` siempre opera sobre la identidad autenticada.
