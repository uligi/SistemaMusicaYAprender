# BL-MVP-017 — Cola de correo y adaptador SMTP interno

## Resultado aceptable

> Los correos se envían desde trabajos reintentables, con plantilla versionada y sin bloquear la transacción de cuenta.

## Diseño

- La transacción de negocio escribe `email.delivery.requested` en `ops.outbox_message`.
- El payload persistido contiene solo identificadores opacos, código/versión de plantilla e idioma; no guarda destinatario, token ni cuerpo del mensaje.
- `EmailJobProjectionConsumer` convierte el evento en un `ops.background_job` de tipo `EMAIL_DELIVERY`.
- `EmailDeliveryJobDispatcher` reclama el trabajo con lease, realiza SMTP fuera de la transacción que creó la cuenta y registra cada resultado en `ops.job_attempt`.
- Se reutiliza la política de máximo tres intentos, retroceso exponencial y jitter de BL-MVP-015.
- La plantilla se selecciona por `(TemplateCode, TemplateVersion, LanguageTag)`.
- `MailKitEmailSender` es el adaptador SMTP reemplazable. El entorno local usa Mailpit.
- Los logs y métricas no registran dirección del destinatario, token ni cuerpo.

## Semántica de entrega

La cola y el trabajo lógico son deduplicables en PostgreSQL. SMTP es un efecto externo y no ofrece una transacción distribuida con PostgreSQL. El adaptador usa un `Message-Id` determinista basado en `DeliveryId` para trazabilidad y eventual deduplicación por un relay que la soporte, pero no se afirma una garantía física de exactly-once después de que un servidor SMTP haya aceptado el mensaje y el proceso falle antes de confirmar el resultado local.

## Verificación

`EmailDeliveryVerifier` demuestra con datos sintéticos que:

1. encolar correo no requiere contactar SMTP;
2. el outbox no persiste dirección ni token;
3. el evento crea un trabajo `EMAIL_DELIVERY`;
4. un primer fallo SMTP queda como `RETRY_WAIT`;
5. el segundo intento entrega mediante Mailpit;
6. existen un intento fallido y uno exitoso;
7. Mailpit contiene exactamente un mensaje sintético con plantilla `ACCOUNT_VERIFICATION` v1.

BL-MVP-017 no implementa todavía el token de verificación de cuenta; eso corresponde a BL-MVP-025.

## Evidencia append-only

El verificador no elimina `ops.job_attempt` ni su `ops.background_job` asociado. Esa evidencia es append-only por diseño físico y forma parte de la trazabilidad operativa. Cada ejecución del verificador usa UUID nuevos, por lo que las repeticiones no colisionan entre sí ni alteran evidencia previa.
