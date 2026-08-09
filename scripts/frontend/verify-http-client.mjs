import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const repoRoot = process.cwd();
const sourceRoot = join(repoRoot, 'apps/web/src/data/http');
const runtimeFiles = [
  'types.ts',
  'retry-policy.ts',
  'read-cache.ts',
  'problem-details.ts',
  'request-state.ts',
  'http-client.ts',
  'index.ts',
];

const requiredFiles = [
  ...runtimeFiles.map((file) => join(sourceRoot, file)),
  join(sourceRoot, 'HttpClientContractFixture.ts'),
  join(repoRoot, 'docs/engineering/frontend/http-data-client.md'),
  join(repoRoot, 'infrastructure/containers/web/nginx.conf'),
];

const readUtf8 = (path) => readFile(path, 'utf8');

async function assertFile(path) {
  try {
    await readUtf8(path);
  } catch {
    throw new Error(`Falta archivo requerido por BL-MVP-021: ${relative(repoRoot, path)}`);
  }
}

for (const path of requiredFiles) {
  await assertFile(path);
}

const httpClientSource = await readUtf8(join(sourceRoot, 'http-client.ts'));
const retrySource = await readUtf8(join(sourceRoot, 'retry-policy.ts'));
const problemSource = await readUtf8(join(sourceRoot, 'problem-details.ts'));
const requestStateSource = await readUtf8(join(sourceRoot, 'request-state.ts'));
const fixtureSource = await readUtf8(join(sourceRoot, 'HttpClientContractFixture.ts'));
const nginxSource = await readUtf8(join(repoRoot, 'infrastructure/containers/web/nginx.conf'));
const documentation = await readUtf8(
  join(repoRoot, 'docs/engineering/frontend/http-data-client.md'),
);

assert.match(httpClientSource, /DEFAULT_BASE_URL\s*=\s*['"]\/api\/v1['"]/);
assert.match(httpClientSource, /credentials:\s*['"]same-origin['"]/);
assert.match(httpClientSource, /Accept-Language/);
assert.match(httpClientSource, /application\/problem\+json/);
assert.match(httpClientSource, /If-Match/);
assert.match(httpClientSource, /If-None-Match/);
assert.match(httpClientSource, /Idempotency-Key/);
assert.match(httpClientSource, /cacheMode/);
assert.match(httpClientSource, /onStateChange/);
assert.match(httpClientSource, /resolveApiUrl/);
assert.match(httpClientSource, /debe permanecer dentro de la base API configurada/);
assert.doesNotMatch(httpClientSource, /localStorage|sessionStorage|Authorization/);

assert.match(retrySource, /MAX_HTTP_ATTEMPTS\s*=\s*3/);
assert.match(retrySource, /408,\s*425,\s*429,\s*502,\s*503,\s*504/);
assert.match(retrySource, /method === ['"]GET['"] \|\| method === ['"]HEAD['"]/);
assert.match(retrySource, /idempotencyKey/);
assert.match(retrySource, /exponential/);
assert.match(retrySource, /jitter/);

assert.match(problemSource, /application\/problem\+json/);
assert.match(problemSource, /correlation_id/);
assert.match(problemSource, /code:/);
assert.match(problemSource, /dataPreserved/);
assert.match(problemSource, /correction/);
assert.doesNotMatch(problemSource, /\.detail\b|\.title\b/);

assert.match(requestStateSource, /UI-EST-11/);
assert.match(requestStateSource, /UI-EST-12/);
assert.match(requestStateSource, /UI-EST-10/);
assert.match(requestStateSource, /UI-EST-09/);
assert.match(fixtureSource, /怪獣/);
assert.match(fixtureSource, /ifMatch/);
assert.match(fixtureSource, /idempotencyKey/);

assert.match(nginxSource, /location \/api\/v1\//);
assert.match(nginxSource, /proxy_pass http:\/\/api:8080\/api\/v1\//);

for (const requiredPhrase of [
  'cancelación',
  'etag',
  'problemdetails',
  'idempotency-key',
  'ui-est-11',
  'ui-est-12',
  'di-mvp-05',
  'di-mvp-08',
  'same-origin',
  'todas las variantes de idioma',
  'no pueden escapar de la base',
]) {
  assert.ok(
    documentation.toLowerCase().includes(requiredPhrase),
    `Falta documentación: ${requiredPhrase}`,
  );
}

const tempRoot = await mkdtemp(join(tmpdir(), 'musica-aprender-bl021-'));

try {
  const compilerConfigPath = join(tempRoot, 'tsconfig.runtime.json');
  const compilerConfig = {
    compilerOptions: {
      target: 'ES2022',
      lib: ['ES2022', 'DOM', 'DOM.Iterable'],
      module: 'ESNext',
      moduleResolution: 'Bundler',
      strict: true,
      noUncheckedIndexedAccess: true,
      exactOptionalPropertyTypes: true,
      noImplicitOverride: true,
      noFallthroughCasesInSwitch: true,
      noUnusedLocals: true,
      noUnusedParameters: true,
      forceConsistentCasingInFileNames: true,
      isolatedModules: true,
      skipLibCheck: true,
      noEmit: false,
      noEmitOnError: true,
      incremental: false,
      rootDir: sourceRoot,
      outDir: tempRoot,
    },
    include: [],
    files: runtimeFiles.map((file) => join(sourceRoot, file)),
  };

  await writeFile(compilerConfigPath, `${JSON.stringify(compilerConfig, null, 2)}\n`, 'utf8');

  const compile =
    process.platform === 'win32'
      ? spawnSync(
          process.env.ComSpec || 'cmd.exe',
          ['/d', '/c', 'npm.cmd', 'exec', '--', 'tsc', '-p', compilerConfigPath],
          {
            cwd: repoRoot,
            encoding: 'utf8',
            stdio: 'pipe',
            windowsHide: true,
          },
        )
      : spawnSync('npm', ['exec', '--', 'tsc', '-p', compilerConfigPath], {
          cwd: repoRoot,
          encoding: 'utf8',
          stdio: 'pipe',
        });

  if (compile.error || compile.status !== 0) {
    const diagnostics = [
      compile.error ? `spawn error: ${compile.error.message}` : '',
      compile.stdout,
      compile.stderr,
      `status: ${String(compile.status)}`,
      compile.signal ? `signal: ${compile.signal}` : '',
    ]
      .filter(Boolean)
      .join('\n')
      .trim();
    assert.fail(
      `El compilador TypeScript del proyecto no pudo emitir el fixture BL-MVP-021.\n${diagnostics}`,
    );
  }

  await writeFile(join(tempRoot, 'package.json'), '{"type":"module"}\n', 'utf8');
  const moduleUrl = `${pathToFileURL(join(tempRoot, 'index.js')).href}?v=${Date.now()}`;
  const { createHttpClient, MAX_HTTP_ATTEMPTS } = await import(moduleUrl);

  assert.equal(MAX_HTTP_ATTEMPTS, 3);

  // 1) Cancelación: una señal ya abortada no dispara fetch ni se confunde con error de red.
  {
    let fetchCalls = 0;
    const controller = new AbortController();
    controller.abort();
    const client = createHttpClient(
      {},
      {
        fetcher: async () => {
          fetchCalls += 1;
          throw new Error('fetch no debe ejecutarse');
        },
        sleep: async () => {},
      },
    );

    const result = await client.get('/songs/kaiju', { signal: controller.signal });
    assert.equal(result.kind, 'cancelled');
    assert.equal(fetchCalls, 0);
  }

  // 2) ETag: primera lectura guarda ETag; lectura vencida revalida con If-None-Match y 304 reutiliza datos.
  {
    let now = 0;
    let fetchCalls = 0;
    const seenIfNoneMatch = [];
    const client = createHttpClient(
      {},
      {
        now: () => now,
        random: () => 0,
        sleep: async () => {},
        fetcher: async (_url, init) => {
          fetchCalls += 1;
          const headers = new Headers(init?.headers);
          seenIfNoneMatch.push(headers.get('if-none-match'));
          assert.equal(init?.credentials, 'same-origin');
          assert.equal(headers.get('accept-language'), 'es-CR');

          if (fetchCalls === 1) {
            return new Response(JSON.stringify({ slug: 'kaiju', titleJa: '怪獣' }), {
              status: 200,
              headers: {
                'content-type': 'application/json; charset=utf-8',
                etag: '"song-v1"',
                'x-correlation-id': 'corr-etag-001',
              },
            });
          }

          return new Response(null, {
            status: 304,
            headers: { 'x-correlation-id': 'corr-etag-002' },
          });
        },
      },
    );

    const first = await client.get('/songs/kaiju');
    assert.equal(first.ok, true);
    assert.equal(first.kind === 'success' ? first.data.titleJa : null, '怪獣');
    assert.equal(first.kind === 'success' ? first.etag : null, '"song-v1"');

    now = 6_000;
    const second = await client.get('/songs/kaiju');
    assert.equal(second.ok, true);
    assert.equal(second.kind === 'success' ? second.fromCache : false, true);
    assert.equal(second.kind === 'success' ? second.data.titleJa : null, '怪獣');
    assert.deepEqual(seenIfNoneMatch, [null, '"song-v1"']);
  }

  // 3) ProblemDetails: usa code/correlation y estructura recuperable; no propaga detail libre a la UI.
  {
    const states = [];
    const client = createHttpClient(
      {},
      {
        sleep: async () => {},
        fetcher: async () =>
          new Response(
            JSON.stringify({
              type: 'https://example.test/problems/validation',
              title: 'RAW TITLE - NO RENDER',
              detail: 'RAW DETAIL - NO RENDER',
              status: 422,
              code: 'validation.invalid',
              correlation_id: 'corr-problem-001',
              errors: { email: ['mensaje libre del servidor'] },
            }),
            {
              status: 422,
              headers: { 'content-type': 'application/problem+json' },
            },
          ),
      },
    );

    const result = await client.post(
      '/accounts',
      { email: 'x' },
      {
        onStateChange: (state) => states.push(state),
      },
    );

    assert.equal(result.ok, false);
    assert.equal(result.kind, 'problem');
    if (result.kind === 'problem') {
      assert.equal(result.problem.code, 'validation.invalid');
      assert.equal(result.problem.correlationId, 'corr-problem-001');
      assert.equal(result.problem.kind, 'validation');
      assert.equal(result.problem.dataPreserved, true);
      assert.equal(result.problem.fieldErrors[0]?.field, 'email');
      const serialized = JSON.stringify(result.problem);
      assert.equal(serialized.includes('RAW DETAIL'), false);
      assert.equal(serialized.includes('RAW TITLE'), false);
      assert.equal(serialized.includes('mensaje libre del servidor'), false);
    }
    assert.deepEqual(
      states.map((state) => state.uiState),
      ['UI-EST-11', 'UI-EST-09'],
    );
  }

  // 4) GET transitorio: máximo tres intentos, backoff inyectable y éxito final.
  {
    let fetchCalls = 0;
    const delays = [];
    const client = createHttpClient(
      {},
      {
        random: () => 0,
        sleep: async (delayMs) => delays.push(delayMs),
        fetcher: async () => {
          fetchCalls += 1;
          if (fetchCalls < 3) {
            return new Response(null, { status: 503 });
          }
          return new Response(JSON.stringify({ ok: true }), {
            status: 200,
            headers: { 'content-type': 'application/json' },
          });
        },
      },
    );

    const result = await client.get('/catalog');
    assert.equal(result.ok, true);
    assert.equal(fetchCalls, 3);
    assert.deepEqual(delays, [150, 300]);
  }

  // 5) POST sin Idempotency-Key no se reintenta automáticamente.
  {
    let fetchCalls = 0;
    const client = createHttpClient(
      {},
      {
        sleep: async () => {},
        fetcher: async () => {
          fetchCalls += 1;
          return new Response(null, { status: 503 });
        },
      },
    );

    const result = await client.post('/attempts', { answer: 'a' });
    assert.equal(result.ok, false);
    assert.equal(fetchCalls, 1);
  }

  // 6) POST con Idempotency-Key sí puede reintentar hasta 3 y solo confirma al recibir éxito.
  {
    let fetchCalls = 0;
    const states = [];
    const client = createHttpClient(
      {},
      {
        random: () => 0,
        sleep: async () => {},
        fetcher: async (_url, init) => {
          fetchCalls += 1;
          const headers = new Headers(init?.headers);
          assert.equal(headers.get('idempotency-key'), 'attempt-fixed-001');
          assert.equal(headers.get('content-type'), 'application/json; charset=utf-8');
          if (fetchCalls < 3) {
            return new Response(null, { status: 503 });
          }
          return new Response(JSON.stringify({ accepted: true }), {
            status: 201,
            headers: {
              'content-type': 'application/json',
              etag: '"attempt-v1"',
              'x-correlation-id': 'corr-write-001',
            },
          });
        },
      },
    );

    const result = await client.post(
      '/attempts',
      { answer: '怪獣' },
      {
        idempotencyKey: 'attempt-fixed-001',
        onStateChange: (state) => states.push(state),
      },
    );

    assert.equal(result.ok, true);
    assert.equal(fetchCalls, 3);
    assert.deepEqual(
      states.map((state) => state.uiState),
      ['UI-EST-11', 'UI-EST-12'],
    );
    assert.equal(states[1]?.phase, 'confirmed');
    assert.equal(
      states[1]?.phase === 'confirmed' ? states[1].correlationId : null,
      'corr-write-001',
    );
  }

  // 7) If-Match: un 412 se vuelve conflicto UI-EST-10 y nunca se reintenta a ciegas.
  {
    let fetchCalls = 0;
    const states = [];
    const client = createHttpClient(
      {},
      {
        sleep: async () => {},
        fetcher: async (_url, init) => {
          fetchCalls += 1;
          const headers = new Headers(init?.headers);
          assert.equal(headers.get('if-match'), '"draft-v4"');
          return new Response(
            JSON.stringify({
              status: 412,
              code: 'concurrency.etag',
              correlation_id: 'corr-412-001',
            }),
            { status: 412, headers: { 'content-type': 'application/problem+json' } },
          );
        },
      },
    );

    const result = await client.patch(
      '/drafts/1',
      { text: '更新' },
      {
        ifMatch: '"draft-v4"',
        onStateChange: (state) => states.push(state),
      },
    );

    assert.equal(result.ok, false);
    assert.equal(fetchCalls, 1);
    assert.deepEqual(
      states.map((state) => state.uiState),
      ['UI-EST-11', 'UI-EST-10'],
    );
  }

  // 8) Cancelación durante lectura de body: tampoco se degrada a problema inesperado.
  {
    const controller = new AbortController();
    const client = createHttpClient(
      {},
      {
        sleep: async () => {},
        fetcher: async () => {
          const response = new Response(JSON.stringify({ ok: true }), {
            status: 200,
            headers: { 'content-type': 'application/json' },
          });

          Object.defineProperty(response, 'json', {
            value: async () => {
              controller.abort();
              throw new DOMException('Body cancelled.', 'AbortError');
            },
          });

          return response;
        },
      },
    );

    const result = await client.get('/cancel-during-body', { signal: controller.signal });
    assert.equal(result.kind, 'cancelled');
  }

  // 9) Invalidación por prefijo: limpia subrutas y todas las variantes de idioma, sin tocar siblings.
  {
    let getCalls = 0;
    const client = createHttpClient(
      {},
      {
        sleep: async () => {},
        fetcher: async (url, init) => {
          const method = init?.method ?? 'GET';
          const headers = new Headers(init?.headers);

          if (method === 'GET') {
            getCalls += 1;
            return new Response(
              JSON.stringify({
                url,
                locale: headers.get('accept-language'),
                call: getCalls,
              }),
              {
                status: 200,
                headers: {
                  'content-type': 'application/json',
                  etag: `"cache-${getCalls}"`,
                },
              },
            );
          }

          return new Response(null, { status: 204 });
        },
      },
    );

    await client.get('/preferences', { locale: 'es-CR' });
    await client.get('/preferences/details', { locale: 'en' });
    await client.get('/preferences-other', { locale: 'en' });
    assert.equal(getCalls, 3);

    await client.patch(
      '/preferences',
      { romajiVisible: true },
      {
        idempotencyKey: 'preferences-invalidate-001',
        invalidate: ['/preferences'],
      },
    );

    await client.get('/preferences', { locale: 'es-CR' });
    await client.get('/preferences/details', { locale: 'en' });
    await client.get('/preferences-other', { locale: 'en' });

    assert.equal(getCalls, 5);
  }

  // 10) Confinamiento: rutas con dot-segments no pueden escapar de /api/v1.
  {
    let fetchCalls = 0;
    const client = createHttpClient(
      {},
      {
        sleep: async () => {},
        fetcher: async () => {
          fetchCalls += 1;
          return new Response('{}', {
            status: 200,
            headers: { 'content-type': 'application/json' },
          });
        },
      },
    );

    await assert.rejects(
      () => client.get('/../health'),
      /permanecer dentro de la base API configurada/,
    );
    await assert.rejects(
      () => client.get('/%2e%2e/health'),
      /permanecer dentro de la base API configurada/,
    );
    assert.equal(fetchCalls, 0);
  }
} finally {
  await rm(tempRoot, { recursive: true, force: true });
}

console.log(
  'OK: BL-MVP-021 cliente HTTP tipado verificado: cancelación, ETag, ProblemDetails, reintentos seguros y estados guardando/confirmado.',
);
