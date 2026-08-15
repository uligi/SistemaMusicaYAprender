import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '16000000-0000-7000-8000-000000000001';
const lyricsRevisionId = '16000000-0000-7000-8000-000000000002';
const sourceId = '16000000-0000-7000-8000-000000000003';
const videoId = 'a8dgNdJVluc';

const synchronizationContext = {
  recordingId,
  lyricsRevisionId,
  lyricsRevisionNo: 3,
  sources: [
    {
      sourceId,
      providerCode: 'YOUTUBE',
      externalRef: videoId,
      durationMs: 240000,
      sourceOffsetMs: 0,
      statusCode: 'DRAFT',
      timingRevision: null,
    },
  ],
};

const lyrics = {
  exists: true,
  revision: {
    lyricsRevisionId,
    recordingId,
    revisionNo: 3,
    parentRevisionId: null,
    statusCode: 'DRAFT',
    createdBy: '16000000-0000-7000-8000-000000000004',
    createdAt: '2026-08-14T00:00:00Z',
    checksumSha256: 'a'.repeat(64),
    version: 3,
    sections: [],
  },
};

const karaokePreview = {
  previewMode: 'DRAFT',
  providerCode: 'YOUTUBE',
  externalRef: videoId,
  lyricsRevisionNo: 3,
  lyricsStatusCode: 'DRAFT',
  timingStatusCode: 'DRAFT',
  translationStatusCode: 'DRAFT',
  analysisStatusCode: 'DRAFT',
  timeline: {
    available: true,
    maximumPrecision: 'TOKEN',
    offsetMs: 0,
    lines: [
      {
        sectionOrder: 0,
        lineNo: 1,
        japaneseText: '怪獣です',
        speakerLabel: null,
        precisionCode: 'TOKEN',
        startMs: 0,
        endMs: 3000,
        tokens: [
          { tokenNo: 1, surface: '怪獣', startMs: 0, endMs: 1500 },
          { tokenNo: 2, surface: 'です', startMs: 1500, endMs: 3000 },
        ],
      },
    ],
  },
  layers: {
    available: true,
    targetLanguage: 'es',
    hasFurigana: true,
    hasRomaji: true,
    hasSpanish: true,
    lines: [
      {
        sectionOrder: 0,
        sectionLabel: 'Verso 1',
        lineNo: 1,
        japaneseText: '怪獣です',
        speakerLabel: null,
        tokens: [
          {
            tokenNo: 1,
            surface: '怪獣',
            startOffset: 0,
            endOffset: 2,
            readings: [
              {
                readingKana: 'かいじゅう',
                furigana: 'かいじゅう',
                romaji: 'kaijū',
                readingType: 'PRIMARY',
              },
            ],
          },
          {
            tokenNo: 2,
            surface: 'です',
            startOffset: 2,
            endOffset: 4,
            readings: [
              {
                readingKana: 'です',
                furigana: null,
                romaji: 'desu',
                readingType: 'PRIMARY',
              },
            ],
          },
        ],
        translations: [
          {
            variantCode: 'NATURAL',
            translatedText: 'Soy un monstruo.',
            displayOrder: 1,
          },
        ],
      },
    ],
  },
};

const iframeApi = `
(() => {
  let currentTime = 0;
  let currentEvents = null;

  window.__karaokePreviewSeek = (seconds) => {
    currentTime = seconds;
    currentEvents?.onStateChange({ data: 3 });
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

async function mockBase(page: import('@playwright/test').Page) {
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

  await page.route('**/api/v1/editorial/song-drafts/*/synchronization-context', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(synchronizationContext),
    });
  });

  await page.route('**/api/v1/editorial/song-drafts/*/lyrics-revisions/latest', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(lyrics),
    });
  });

  await page.route('**/api/v1/editorial/song-drafts/*/karaoke-preview?**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(karaokePreview),
    });
  });

  await page.route('https://www.youtube-nocookie.com/embed/**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'text/html; charset=utf-8',
      body: '<!doctype html><html><body><p>Fixture</p></body></html>',
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

test.describe('BL-MVP-060/063 · previsualización editorial de karaoke', () => {
  test('cambia entre los dos paneles y prueba karaoke DRAFT sin consultar publicación', async ({
    page,
  }) => {
    const publicRequests: string[] = [];
    page.on('request', (request) => {
      if (request.url().includes('/api/v1/public/')) {
        publicRequests.push(request.url());
      }
    });

    await mockBase(page);
    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    await expect(page.getByRole('button', { name: 'Revisión de sincronización' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );

    await page.getByRole('button', { name: 'Previsualización de Karaoke' }).click();

    await expect(page.locator('[data-editorial-karaoke-preview]')).toBeVisible();
    await expect(page.getByText('VISTA PREVIA EDITORIAL · NO PUBLICA')).toBeVisible();
    await expect(page.getByText('Soy un monstruo.')).toBeVisible();
    await expect(page.locator('[data-karaoke-line="0:1"] ruby')).toContainText('かいじゅう');

    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();

    await page.evaluate(() => {
      const target = window as typeof window & {
        __karaokePreviewSeek?: (seconds: number) => void;
      };
      target.__karaokePreviewSeek?.(1);
    });

    await expect(page.locator('[data-karaoke-line="0:1"]')).toHaveAttribute('data-active', 'true');
    await expect(page.locator('[data-karaoke-token="1"]')).toHaveAttribute('data-active', 'true');

    await page.getByRole('button', { name: 'Español' }).click();
    await expect(page.getByText('Soy un monstruo.')).toHaveCount(0);

    expect(publicRequests).toEqual([]);
  });

  test('mantiene ambos paneles accesibles y sin overflow a 320 px', async ({ page }) => {
    await mockBase(page);
    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    await page.getByRole('button', { name: 'Previsualización de Karaoke' }).click();
    await expect(page.locator('[data-editorial-karaoke-preview]')).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
