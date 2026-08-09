import { context, propagation, SpanStatusCode, trace } from '@opentelemetry/api';
import { SeverityNumber } from '@opentelemetry/api-logs';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { BatchLogRecordProcessor, LoggerProvider } from '@opentelemetry/sdk-logs';
import { MeterProvider, PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { BatchSpanProcessor, WebTracerProvider } from '@opentelemetry/sdk-trace-web';

const serviceName = 'musica-aprender-web';
const serviceVersion = '0.1.0';
const scopeName = 'MusicaAprender.Web';

const resource = resourceFromAttributes({
  'service.name': serviceName,
  'service.version': serviceVersion,
});

const telemetryBaseUrl = `${window.location.origin}/otel/v1`;

const tracerProvider = new WebTracerProvider({
  resource,
  spanProcessors: [
    new BatchSpanProcessor(
      new OTLPTraceExporter({
        url: `${telemetryBaseUrl}/traces`,
      }),
    ),
  ],
});

tracerProvider.register();

const tracer = trace.getTracer(scopeName, serviceVersion);

const meterProvider = new MeterProvider({
  resource,
  readers: [
    new PeriodicExportingMetricReader({
      exporter: new OTLPMetricExporter({
        url: `${telemetryBaseUrl}/metrics`,
      }),
      exportIntervalMillis: 5_000,
    }),
  ],
});

const meter = meterProvider.getMeter(scopeName, serviceVersion);

const clientStarts = meter.createCounter('musica_aprender.client.startups', {
  unit: '{startup}',
  description: 'Inicializaciones observables del cliente web.',
});

const bootstrapDuration = meter.createHistogram('musica_aprender.client.bootstrap.duration', {
  unit: 'ms',
  description: 'Duracion de la comprobacion inicial del cliente.',
});

const loggerProvider = new LoggerProvider({
  resource,
  processors: [
    new BatchLogRecordProcessor({
      exporter: new OTLPLogExporter({
        url: `${telemetryBaseUrl}/logs`,
      }),
    }),
  ],
});

const logger = loggerProvider.getLogger(scopeName, serviceVersion);

export function initializeClientTelemetry(): void {
  const correlationId = crypto.randomUUID();
  const started = performance.now();

  clientStarts.add(1, {
    'operation.version': 'v1',
  });

  const span = tracer.startSpan('client.bootstrap', {
    attributes: {
      'app.correlation_id': correlationId,
      'app.operation.version': 'v1',
    },
  });

  const spanContext = trace.setSpan(context.active(), span);
  const carrier: Record<string, string> = {};

  propagation.inject(spanContext, carrier);

  void fetch('/api/health/live', {
    headers: {
      ...carrier,
      'X-Correlation-Id': correlationId,
    },
  })
    .then((response) => {
      const result = response.ok ? 'success' : 'failure';

      span.setAttribute('http.response.status_code', response.status);
      span.setStatus({
        code: response.ok ? SpanStatusCode.OK : SpanStatusCode.ERROR,
      });

      bootstrapDuration.record(performance.now() - started, {
        result,
        'operation.version': 'v1',
      });

      logger.emit({
        severityNumber: response.ok ? SeverityNumber.INFO : SeverityNumber.ERROR,
        severityText: response.ok ? 'INFO' : 'ERROR',
        body: 'client.bootstrap.completed',
        attributes: {
          'app.correlation_id': correlationId,
          trace_id: span.spanContext().traceId,
          span_id: span.spanContext().spanId,
          'operation.version': 'v1',
          result,
        },
      });
    })
    .catch(() => {
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: 'First-party health probe failed.',
      });

      bootstrapDuration.record(performance.now() - started, {
        result: 'failure',
        'operation.version': 'v1',
      });

      logger.emit({
        severityNumber: SeverityNumber.ERROR,
        severityText: 'ERROR',
        body: 'client.bootstrap.failed',
        attributes: {
          'app.correlation_id': correlationId,
          trace_id: span.spanContext().traceId,
          span_id: span.spanContext().spanId,
          'operation.version': 'v1',
          result: 'failure',
        },
      });
    })
    .finally(() => {
      span.end();
    });
}
