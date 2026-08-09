# BL-MVP-006B — Corrección PostgreSQL 18

Los logs confirman el cambio introducido por la imagen oficial de PostgreSQL 18:

- el montaje anterior `postgres-data:/var/lib/postgresql/data` ya no es válido;
- para PostgreSQL 18+ el volumen debe montarse en `/var/lib/postgresql`;
- el contenedor crea internamente el directorio específico de la versión.

Este parche:

1. corrige `compose.yml`;
2. documenta la decisión;
3. detiene el entorno;
4. elimina **solo** el volumen local de PostgreSQL creado con la ruta incorrecta;
5. conserva los volúmenes de MinIO y Mailpit;
6. valida el Compose.

## Uso

Copie la carpeta `scripts` sobre la carpeta `scripts` del repositorio y ejecute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-006b.ps1
```

Si termina en `OK`, ejecute:

```powershell
.\scripts\local\start.ps1
```

Después:

```powershell
.\scripts\local\verify-running.ps1
```
