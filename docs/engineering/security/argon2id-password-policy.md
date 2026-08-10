# Política de credenciales Argon2id — BL-MVP-028

## Alcance

BL-MVP-028 incorpora la contraseña al registro personal de `UI-MVP-005` y crea una credencial activa en `security.credential` dentro de la misma transacción que la cuenta, el perfil, los consentimientos, el desafío de verificación y el outbox. No crea sesión, cookie, CSRF, cierre de sesión, recuperación ni limitación de intentos; esas responsabilidades pertenecen a BL-MVP-026, BL-MVP-027, BL-MVP-029 y BL-MVP-030.

Traza principal: CU-MVP-02 y CU-MVP-03; CA-009, CA-010 y CA-017; RF-M18-018, RF-M18-019, RF-M18-021, RF-M18-022, RF-M18-024 y RF-M18-025; RNF-049 a RNF-052; ADR-008.

## Contrato de política

La política `PASSWORD_V1_2026-08-10`:

- cuenta puntos de código después de normalizar a Unicode NFC;
- acepta de 15 a 128 puntos de código;
- acepta espacios, Unicode y valores sin una composición arbitraria de mayúsculas, números o símbolos;
- permite pegado y gestores de contraseñas mediante `autocomplete="new-password"`;
- rechaza controles, separadores de línea, valores vacíos o compuestos solo por espacios;
- compara el valor completo con una lista local, versionada y determinista de contraseñas comunes o comprometidas;
- no consulta un tercero durante el registro y no envía la contraseña fuera del origen.

La lista local es un piso operativo para el MVP. Su ampliación futura debe conservar versión, revisión de fuente y pruebas; no debe registrar el valor rechazado.

## Derivación y almacenamiento

La dependencia fijada `Konscious.Security.Cryptography.Argon2` 1.3.1 implementa Argon2id. La configuración inicial es:

| Parámetro      |                              Valor |
| -------------- | ---------------------------------: |
| Versión Argon2 |                                 19 |
| Memoria        |                         65 536 KiB |
| Iteraciones    |                                  3 |
| Paralelismo    |                                  1 |
| Sal            | 16 bytes aleatorios por credencial |
| Derivado       |                           32 bytes |
| Normalización  |                                NFC |

Los parámetros son configurables en `PasswordHashing:Argon2id:*`, pero el constructor impide bajar de 19 MiB, dos iteraciones, una vía de paralelismo, 16 bytes de sal o 32 bytes de derivado. También impone máximos defensivos al verificar material persistido para evitar consumo de recursos controlado desde la base.

`security.credential` conserva únicamente:

- `algorithm = ARGON2ID`;
- `hash`, en Base64;
- `parameters`, como JSON compacto con versión, memoria, iteraciones, paralelismo, longitud, sal, normalización y versión de política;
- fecha de cambio y estado activo.

La contraseña no se persiste, cifra, registra ni incorpora a evidencia. La comparación futura usa derivación con los parámetros almacenados y `CryptographicOperations.FixedTimeEquals`.

## Idempotencia sin huella rápida

Un reintento de registro debe distinguir una contraseña modificada sin almacenar el secreto ni un SHA-256 reutilizable para ataques fuera de línea. La API calcula en memoria una HMAC-SHA-256 con propósito separado y la clave externa `identity_password_fingerprint_key`; solo esa huella participa en el resumen canónico de idempotencia. Los búferes de contraseña y huella se limpian cuando la API deja de necesitarlos.

La clave se monta como archivo, no pertenece al repositorio y debe rotarse mediante el procedimiento general de secretos. API y worker reciben el conjunto completo de claves de identidad para mantener un contrato de configuración único; solo la API usa esta clave en BL-MVP-028.

## Evidencia

Las pruebas unitarias cubren Unicode/NFC, límites, bloqueo, sales distintas, verificación y material inválido. Playwright cubre teclado, pegado, `new-password`, foco de corrección, limpieza posterior al éxito, lector de pantalla y reflujo. El smoke real comprueba la fila de credencial, parámetros, ausencia de texto claro, conflicto por cambio de contraseña con la misma clave y un tiempo total de registro de al menos 100 ms en el entorno validado.
