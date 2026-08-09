# BL-MVP-006 — Docker Compose local reproducible

**Backlog:** Crear Docker Compose local reproducible  
**Traza:** DIS; COM; REC  
**SP:** 8  
**Dependencias:** BL-MVP-001 y BL-MVP-002

Resultado aceptable de la línea base: un comando levanta web/API, worker, PostgreSQL,
almacén de objetos de desarrollo, SMTP sink y collector.

## Aplicación

Copie el contenido del ZIP sobre la raíz del repositorio y reemplace archivos.

Después:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-006.ps1
```

Si valida correctamente, levante el entorno:

```powershell
.\scripts\local\start.ps1
```

La primera ejecución descargará imágenes y compilará web/API/worker, por lo que puede tardar varios minutos.

Luego:

```powershell
.\scripts\local\verify-running.ps1
```

No haga commit hasta que la verificación indique que los siete servicios están ejecutándose.
