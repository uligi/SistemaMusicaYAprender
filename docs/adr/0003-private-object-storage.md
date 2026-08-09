# ADR-003 — Almacenamiento privado de objetos en desarrollo

**Estado:** Aceptada para el entorno de desarrollo del MVP
**Fecha:** 2026-08-09
**Traza:** BL-MVP-016; ADR-012; PRI; REC; DAT

## Contexto

La arquitectura aprobada propone en ADR-012 un almacén de objetos privado,
S3-compatible y controlado, en lugar de guardar binarios grandes dentro de PostgreSQL.
El modelo físico ya reserva `ops.stored_object` para metadatos, checksum, retención y
referencia de clave; los bytes permanecen fuera de la base.

## Decisión

El desarrollo local usa el MinIO ya incorporado por BL-MVP-006 como backend S3-compatible.

`IObjectStore` es el contrato estable. La implementación de infraestructura:

- usa un bucket privado sin política anónima;
- no expone métodos de URL pública ni presigned URL;
- genera claves opacas;
- cifra los bytes antes de enviarlos al backend mediante chunks AES-256-GCM autenticados;
- conserva SHA-256 del plaintext, tamaño, media type, propietario, finalidad, retención y
  referencia no secreta de clave;
- exige `owner_module` y `purpose_code` coincidentes para lectura/eliminación;
- mantiene el material criptográfico en el secret store de BL-MVP-009.

`ops.stored_object` sigue siendo el registro lógico mínimo de metadatos. El adaptador de
bytes no comparte un `DbContext`; el propietario de la operación registra el descriptor
mediante los contratos y permisos que correspondan. El verificador BL-MVP-016 usa la
identidad worker ya autorizada sobre `ops` únicamente para demostrar la reconciliación.

## Formato cifrado

La versión inicial se identifica por la cabecera `MAOBJ001`.

Cada chunk de 1 MiB usa AES-256-GCM con nonce único por objeto/chunk y tag de 128 bits.
El checksum SHA-256 se calcula sobre el plaintext y se compara al recuperar el objeto.

La referencia `local-secret://object_store_encryption_key/v1` identifica la clave sin
almacenar su valor en PostgreSQL, configuración no secreta, logs ni Git.

## Consecuencias

- MinIO recibe ciphertext, no plaintext.
- Un GET anónimo a la ruta directa del bucket debe fallar.
- La aplicación debe recuperar objetos por `IObjectStore`, no construyendo URLs directas.
- Cambiar el proveedor de producción no cambia el contrato.
- La selección del proveedor/KMS definitivo de producción permanece como decisión de
  despliegue; este ADR valida el adaptador privado de desarrollo pedido por BL-MVP-016.
