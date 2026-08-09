# Health checks — BL-MVP-007

BL-MVP-007 separa tres conceptos operativos:

- **Liveness**: el proceso de la API está vivo. No consulta dependencias externas.
- **Readiness**: la API puede servir el flujo normal. PostgreSQL es una dependencia crítica.
- **Dependencies**: muestra el estado agregado de dependencias con nombres y mensajes genéricos.

## Endpoints

| Endpoint               | Propósito                            | Dependencias                              |
| ---------------------- | ------------------------------------ | ----------------------------------------- |
| `/health/live`         | Detectar proceso vivo                | Ninguna                                   |
| `/health/ready`        | Determinar si el servicio está listo | PostgreSQL, object store, SMTP, collector |
| `/health/dependencies` | Diagnóstico operacional seguro       | PostgreSQL, object store, SMTP, collector |

## Semántica

- PostgreSQL no disponible → `Unhealthy` y HTTP 503 en readiness/dependencies.
- Object store, SMTP o collector no disponibles → `Degraded` y HTTP 200.
- Liveness permanece independiente de esas dependencias.

La respuesta nunca serializa excepciones, connection strings, URLs, hosts, contraseñas ni claves.
Solo expone nombre lógico, estado, duración y una descripción genérica.

## Verificación local

Con el Compose en ejecución:

```powershell
.\scripts\local\verify-running.ps1
```

Después se puede ejecutar la prueba negativa controlada:

```powershell
.\scripts\local\verify-health-degradation.ps1
```

La prueba detiene temporalmente MinIO, comprueba que el endpoint pase a `Degraded`
sin revelar secretos y vuelve a iniciar el servicio automáticamente.
