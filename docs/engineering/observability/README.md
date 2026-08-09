# Observabilidad y correlación — BL-MVP-008

BL-MVP-008 instrumenta API, worker y cliente web con OpenTelemetry.

## Convenciones

- API: `musica-aprender-api`, versión `0.1.0`.
- Worker: `musica-aprender-worker`, versión `0.1.0`.
- Cliente web: `musica-aprender-web`, versión `0.1.0`.
- Scopes: `MusicaAprender.Api`, `MusicaAprender.Worker` y `MusicaAprender.Web`.
- El identificador de correlación propio viaja en `X-Correlation-Id`.
- Las trazas web usan además el contexto W3C (`traceparent`) cuando está disponible.
- Los nombres de operaciones y señales se consideran contratos versionados.

## Señales

### API

La API emite trazas HTTP, trazas de `HttpClient`, métricas de ASP.NET Core/runtime,
métricas propias y logs estructurados. El scope agrega `correlation_id`, `trace_id`,
`span_id`, servicio y versión sin guardar cuerpos de solicitud.

### Worker

El worker emite un span, una métrica y un log estructurado desde el heartbeat.
Los trabajos posteriores deberán conservar el mismo patrón de correlación.

### Cliente web

El cliente emite el span `client.bootstrap`, las métricas
`musica_aprender.client.startups` y `musica_aprender.client.bootstrap.duration`,
y un log de resultado. La comprobación inicial llama únicamente a un endpoint propio.

## Transporte local

- API y worker exportan OTLP/gRPC a `otel-collector:4317`.
- El navegador exporta OTLP/HTTP por el mismo origen mediante `/otel/v1/...`.
- Nginx reenvía `/otel/` al collector por `4318`.
- El collector usa `debug` como evidencia local en este incremento.

## Minimización

La instrumentación no debe registrar contraseñas, tokens, connection strings,
notas libres, respuestas educativas completas, claves de objeto ni cuerpos HTTP.
La comprobación local busca además las credenciales de desarrollo conocidas para
detectar una exposición accidental.

Los paneles, alertas, sintéticos, retención operacional y auditoría persistente se
completan en los PBI posteriores que los tienen como resultado verificable.
