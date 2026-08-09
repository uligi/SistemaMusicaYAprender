# BL-MVP-009 — Configuración por ambiente y secret store

**Fase:** F0 — Cimientos  
**Épica:** EP-00 — Ingeniería y repositorio  
**Tipo:** Habilitador  
**Traza:** SEG; PRI; REC  
**SP:** 5  
**Dependencia:** BL-MVP-006

Resultado aceptable: ningún secreto vive en repositorio o M19; configuración efectiva y secretos
se inyectan, validan y rotan por separado.

## Qué cambia

- `.env.example` queda exclusivamente para configuración no secreta.
- `secrets/local/` se usa como store local y nunca se rastrea.
- Docker Compose monta secretos como archivos, no como valores en `environment`.
- API y worker construyen su configuración efectiva al iniciar.
- PostgreSQL y MinIO consumen archivos secretos.
- CI escanea el árbol rastreado y usa secretos efímeros solo para validar Compose.
- Hay una prueba reproducible de rotación sin recompilar imágenes.

## Aplicación

Extraiga el ZIP sobre la raíz del repositorio y reemplace archivos.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-009.ps1
```

El script también migra la base local existente desde las credenciales de desarrollo anteriores
hacia el nuevo secreto generado, por lo que no es necesario borrar el volumen PostgreSQL.

Después:

```powershell
.\scripts\local\start.ps1
.\scripts\local\verify-running.ps1
.\scripts\local\verify-secret-rotation.ps1
```

No haga commit hasta que las tres verificaciones terminen correctamente.
