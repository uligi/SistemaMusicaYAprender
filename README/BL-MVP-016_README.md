# BL-MVP-016 — IObjectStore y almacenamiento privado de desarrollo

## Resultado aceptable

> Los objetos conservan checksum, metadatos, cifrado y autorización; ningún recurso privado
> se sirve por URL pública directa.

## Implementación

- `IObjectStore` vive en BuildingBlocks Contracts.
- MinIO es el adaptador S3-compatible del entorno local.
- El bucket `musica-aprender-private` permanece privado.
- Los bytes se cifran antes del `PUT` con el formato autenticado `MAOBJ001`
  (AES-256-GCM por chunks).
- `stored_object` conserva la clave lógica, media type, tamaño, SHA-256, referencia de
  cifrado, retención, propietario/finalidad y estado.
- El contrato nunca devuelve URL pública ni presigned URL.
- Lectura y eliminación exigen coincidencia de `owner_module` y `purpose_code`.
- `object_store_encryption_key` vive únicamente en el secret store montado por archivo.

## Validación

Local:

```powershell
.\scripts\database\verify-object-store.ps1
```

El verificador comprueba:

1. descriptor + fila `ops.stored_object`;
2. checksum SHA-256;
3. denegación por owner/finalidad incorrectos;
4. GET anónimo directo no exitoso;
5. ciphertext en MinIO, no plaintext;
6. round-trip autorizado;
7. eliminación autorizada.

CI ejecuta el mismo escenario con MinIO efímero y publica
`artifacts/postgres/object-store-summary.txt`.

## Límites

BL-MVP-016 no agrega endpoints de carga/descarga de negocio, no crea una migración nueva y no
amplía grants PostgreSQL. La identidad worker ya tiene DML sobre `ops`; la API conserva los
privilegios establecidos por BL-MVP-012.
