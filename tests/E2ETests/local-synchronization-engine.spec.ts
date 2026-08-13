import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import {
  createLocalSynchronizationIndex,
  emptySynchronizationTimeline,
  locateSynchronization,
  type SynchronizationTimeline,
} from '../../apps/web/src/features/player/synchronization/LocalSynchronizationEngine';

const slug = 'kaiju-0123456789abcdefabcd';
const recordingId = 'efc89b51-cfa6-5a56-91b1-6bc03942a971';
const videoId = 'a8dgNdJVluc';

const timeline: SynchronizationTimeline = {
  available: true,
  maximumPrecision: 'TOKEN',
  offsetMs: 100,
  lines: [
    {
      sectionOrder: 0,
      lineNo: 1,
      japaneseText: '怪獣です',
      speakerLabel: 'voz principal',
      precisionCode: 'TOKEN',
      startMs: 1000,
      endMs: 2200,
      tokens: [
        { tokenNo: 1, surface: '怪獣', startMs: 1000, endMs: 1500 },
        { tokenNo: 2, surface: 'です', startMs: 1700, endMs: 2200 },
      ],
    },
    {
      sectionOrder: 0,
      lineNo: 2,
      japaneseText: '何度でも',
      speakerLabel: null,
      precisionCode: 'LINE',
      startMs: 2500,
      endMs: 4200,
      tokens: [],
    },
  ],
};

const detail = {
  slug,
  canonicalTitle: '怪獣',
  recordingTitle: 'Kaiju',
  recordingDurationMs: 10_000,
  artistName: 'サカナクション',
  providerCode: 'YOUTUBE',
  territoryCode: 'CR',
  languageTag: 'es',
  availabilityValidFrom: '2026-08-13T00:00:00Z',
  availabilityValidTo: null,
  availableComponents: ['CATALOG', 'LYRICS', 'TIMING'],
  sourceExternalRef: videoId,
};

const iframeApi = `
(() => {
  let currentTime = 0;
  let currentEvents = null;

  window.__bl059Seek = (seconds) => {
    currentTime = seconds;
    currentEvents?.onStateChange({ data: 3 });
  };

  window.__bl059State = (state) => {
    currentEvents?.onStateChange({ data: state });
  };

  window.YT = {
    Player: function(element, options) {
      currentEvents = options.events;
      this.destroy = () => {};
      this.playVideo = () => options.events.onStateChange({ data: 1 });
      this.pauseVideo = () => options.events.onStateChange({ data: 2 });
      this.seekTo = (seconds) => {
        currentTime = seconds;
        options.events.onStateChange({ data: 3 });
      };
      this.getCurrentTime = () => currentTime;
      queueMicrotask(() => options.events.onReady({ target: this }));
    }
  };

  window.onYouTubeIframeAPIReady?.();
})();
`;

async function mockYoutube(page: import('@playwright/test').Page) {
  await page.route('https://www.youtube-nocookie.com/embed/**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'text/html; charset=utf-8',
      body: `<!doctype html>
<html lang="es">
  <head><meta charset="utf-8"><title>BL059 fixture</title></head>
  <body><div data-youtube-e2e-fixture="true"><p>Fixture externa neutral.</p></div></body>
</html>`,
    });
  });

  await page.route('https://www.youtube.com/iframe_api', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/javascript',
      body: iframeApi,
    });
  });
}

async function seek(page: import('@playwright/test').Page, seconds: number) {
  await page.evaluate((value) => {
    const target = window as typeof window & { __bl059Seek?: (seconds: number) => void };
    target.__bl059Seek?.(value);
  }, seconds);
}

test.describe('BL-MVP-059 · motor local de sincronización', () => {
  test('usa búsqueda binaria, aplica offset y degrada TOKEN → LINE → NONE', () => {
    const index = createLocalSynchronizationIndex(timeline);

    const token = locateSynchronization(index, 1200);
    expect(token.level).toBe('TOKEN');
    expect(token.line?.lineNo).toBe(1);
    expect(token.token?.surface).toBe('怪獣');

    // 1600 ms cae dentro de la línea efectiva, pero en el hueco entre tokens.
    const lineFallback = locateSynchronization(index, 1600);
    expect(lineFallback.level).toBe('LINE');
    expect(lineFallback.line?.lineNo).toBe(1);
    expect(lineFallback.token).toBeNull();

    const secondLine = locateSynchronization(index, 2800);
    expect(secondLine.level).toBe('LINE');
    expect(secondLine.line?.lineNo).toBe(2);

    const gap = locateSynchronization(index, 2400);
    expect(gap.level).toBe('NONE');
    expect(gap.line).toBeNull();

    const empty = locateSynchronization(
      createLocalSynchronizationIndex(emptySynchronizationTimeline()),
      1200,
    );
    expect(empty.level).toBe('NONE');
  });

  test('resuelve 100 búsquedas de seek sobre 300 líneas sin barrido lineal del índice', () => {
    const largeTimeline: SynchronizationTimeline = {
      available: true,
      maximumPrecision: 'LINE',
      offsetMs: 0,
      lines: Array.from({ length: 300 }, (_, index) => ({
        sectionOrder: Math.floor(index / 30),
        lineNo: index + 1,
        japaneseText: `行${index + 1}`,
        speakerLabel: null,
        precisionCode: 'LINE',
        startMs: index * 1000,
        endMs: index * 1000 + 800,
        tokens: [],
      })),
    };

    const index = createLocalSynchronizationIndex(largeTimeline);
    const started = performance.now();

    for (let operation = 0; operation < 100; operation += 1) {
      const line = (operation * 17) % 300;
      const snapshot = locateSynchronization(index, line * 1000 + 100);
      expect(snapshot.line?.lineNo).toBe(line + 1);
    }

    expect(performance.now() - started).toBeLessThan(100);
  });

  test('UI-MVP-009 resincroniza tras evento confirmado del player sin mover foco', async ({
    page,
  }) => {
    await mockYoutube(page);

    await page.route('**/api/v1/public/catalog/songs/*/synchronization*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(timeline),
      });
    });

    await page.route('**/api/v1/public/catalog/songs/*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(detail),
      });
    });

    await page.goto(`/aprender/${slug}`);
    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();

    const back = page.getByRole('link', { name: 'Volver a la ficha pública' });
    await back.focus();

    const started = Date.now();
    await seek(page, 1.2);
    const synchronizedStatus = page.locator('[data-local-synchronization]');
    await expect(synchronizedStatus).toContainText('Línea 1:', { timeout: 300 });
    await expect(synchronizedStatus).toContainText('怪獣です', { timeout: 300 });
    expect(Date.now() - started).toBeLessThanOrEqual(300);
    await expect(back).toBeFocused();

    await seek(page, 1.6);
    await expect(page.locator('[data-local-synchronization]')).toHaveAttribute(
      'data-sync-level',
      'LINE',
      { timeout: 300 },
    );

    await seek(page, 2.8);
    await expect(synchronizedStatus).toContainText('Línea 2:', { timeout: 300 });
    await expect(synchronizedStatus).toContainText('何度でも', { timeout: 300 });

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('sin tiempos publicados degrada a NONE sin bloquear YouTube ni inventar línea', async ({
    page,
  }) => {
    await mockYoutube(page);

    await page.route('**/api/v1/public/catalog/songs/*/synchronization*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(emptySynchronizationTimeline()),
      });
    });

    await page.route('**/api/v1/public/catalog/songs/*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ...detail, availableComponents: ['CATALOG'] }),
      });
    });

    await page.goto(`/aprender/${slug}`);
    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();

    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();
    await expect(page.locator('[data-local-synchronization]')).toHaveAttribute(
      'data-sync-level',
      'NONE',
    );
    await expect(
      page.getByText('Sin marcas temporales compatibles', { exact: false }),
    ).toBeVisible();
    await expect(page.getByText('Línea 1:', { exact: false })).toHaveCount(0);
  });

  test('UI-MVP-022 usa la revisión DRAFT exacta para previsualizar sin publicar', async ({
    page,
  }) => {
    await mockYoutube(page);

    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'EDITOR',
          roles: ['EDITOR'],
          capabilities: ['EDITORIAL.DRAFT'],
        }),
      });
    });

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/synchronization-context`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            recordingId,
            lyricsRevisionId: '22222222-2222-7222-8222-222222222222',
            lyricsRevisionNo: 2,
            sources: [
              {
                sourceId: '33333333-3333-7333-8333-333333333333',
                providerCode: 'YOUTUBE',
                externalRef: videoId,
                durationMs: 10_000,
                sourceOffsetMs: 0,
                statusCode: 'DRAFT',
                timingRevision: {
                  timingRevisionId: 'aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa',
                  lyricsRevisionId: '22222222-2222-7222-8222-222222222222',
                  sourceId: '33333333-3333-7333-8333-333333333333',
                  revisionNo: 3,
                  offsetMs: timeline.offsetMs,
                  statusCode: 'DRAFT',
                  checksumSha256: 'c'.repeat(64),
                  lines: timeline.lines.map((line, lineIndex) => ({
                    ...line,
                    lineId:
                      lineIndex === 0
                        ? '66666666-6666-7666-8666-666666666666'
                        : '99999999-9999-7999-8999-999999999999',
                    tokens: line.tokens.map((token, tokenIndex) => ({
                      ...token,
                      tokenId:
                        tokenIndex === 0
                          ? '77777777-7777-7777-8777-777777777777'
                          : '88888888-8888-7888-8888-888888888888',
                    })),
                  })),
                },
              },
            ],
          }),
        });
      },
    );

    await page.route('**/api/v1/editorial/song-drafts/*/lyrics-revisions/latest', async (route) => {
      await route.fulfill({
        status: 409,
        contentType: 'application/problem+json',
        body: JSON.stringify({
          title: 'Fixture BL059',
          status: 409,
          detail: 'El editor BL057 no forma parte de esta prueba de previsualización.',
        }),
      });
    });

    let publicSyncRequests = 0;
    page.on('request', (request) => {
      if (request.url().includes('/api/v1/public/catalog/songs/')) {
        publicSyncRequests += 1;
      }
    });

    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);
    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();

    await seek(page, 1.2);
    const editorialStatus = page.locator('[data-local-synchronization]');
    await expect(editorialStatus).toContainText('Línea 1:', { timeout: 300 });
    await expect(editorialStatus).toContainText('怪獣です', { timeout: 300 });

    expect(publicSyncRequests).toBe(0);
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);
    await expect(page.getByText('BL-MVP-059 · MOTOR LOCAL DE SINCRONIZACIÓN')).toBeVisible();
  });

  test('mantiene sincronización local a 320px sin desbordamiento horizontal', async ({ page }) => {
    await mockYoutube(page);

    await page.route('**/api/v1/public/catalog/songs/*/synchronization*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(timeline),
      });
    });

    await page.route('**/api/v1/public/catalog/songs/*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(detail),
      });
    });

    await page.setViewportSize({ width: 320, height: 1000 });
    await page.goto(`/aprender/${slug}`);
    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await seek(page, 1.2);

    await expect(page.locator('[data-local-synchronization]')).toContainText('Línea 1:');
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });
});
