import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const slug = 'kaiju-0123456789abcdefabcd';
const videoId = 'a8dgNdJVluc';

const detail = {
  slug,
  canonicalTitle: '怪獣',
  recordingTitle: 'Kaiju',
  recordingDurationMs: 10_000,
  artistName: 'サカナクション',
  providerCode: 'YOUTUBE',
  territoryCode: 'CR',
  languageTag: 'es',
  availabilityValidFrom: '2026-08-14T00:00:00Z',
  availabilityValidTo: null,
  availableComponents: ['CATALOG', 'LYRICS', 'TIMING', 'TRANSLATION', 'ANALYSIS'],
  sourceExternalRef: videoId,
};

const timeline = {
  available: true,
  maximumPrecision: 'TOKEN',
  offsetMs: 0,
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
        { tokenNo: 2, surface: 'です', startMs: 1500, endMs: 2200 },
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

const layers = {
  available: true,
  targetLanguage: 'es',
  hasFurigana: true,
  hasRomaji: true,
  hasSpanish: true,
  lines: [
    {
      sectionOrder: 0,
      sectionLabel: 'Verso',
      lineNo: 1,
      japaneseText: '怪獣です',
      speakerLabel: 'voz principal',
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
              readingType: 'CONTEXTUAL',
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
              readingType: 'CONTEXTUAL',
            },
          ],
        },
      ],
      translations: [
        {
          variantCode: 'LITERAL',
          translatedText: 'Es un monstruo.',
          displayOrder: 0,
        },
        {
          variantCode: 'NATURAL',
          translatedText: 'Soy un monstruo.',
          displayOrder: 1,
        },
      ],
    },
    {
      sectionOrder: 0,
      sectionLabel: 'Verso',
      lineNo: 2,
      japaneseText: '何度でも',
      speakerLabel: null,
      tokens: [
        {
          tokenNo: 1,
          surface: '何度',
          startOffset: 0,
          endOffset: 2,
          readings: [
            {
              readingKana: 'なんど',
              furigana: '何度[なんど]',
              romaji: null,
              readingType: 'CONTEXTUAL',
            },
          ],
        },
        {
          tokenNo: 2,
          surface: 'でも',
          startOffset: 2,
          endOffset: 4,
          readings: [
            {
              readingKana: 'でも',
              furigana: null,
              romaji: null,
              readingType: 'CONTEXTUAL',
            },
          ],
        },
      ],
      translations: [
        {
          variantCode: 'NATURAL',
          translatedText: 'Una y otra vez.',
          displayOrder: 1,
        },
      ],
    },
  ],
};

const iframeApi = `
(() => {
  let currentTime = 0;
  let currentEvents = null;

  window.__eduSeek = (seconds) => {
    currentTime = seconds;
    currentEvents?.onStateChange({ data: 3 });
  };

  window.__eduCurrent = () => currentTime;

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

async function mockPublishedSong(page: Page) {
  await page.route('**/api/v1/public/catalog/songs/**', async (route) => {
    const path = new URL(route.request().url()).pathname;

    if (path.endsWith('/synchronization')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(timeline),
      });
      return;
    }

    if (path.endsWith('/layers')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(layers),
      });
      return;
    }

    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(detail),
    });
  });
}

async function mockYoutube(page: Page, failApi = false) {
  let embedRequests = 0;
  let apiRequests = 0;

  await page.route('https://www.youtube-nocookie.com/embed/**', async (route) => {
    embedRequests += 1;
    await route.fulfill({
      status: 200,
      contentType: 'text/html; charset=utf-8',
      body: '<!doctype html><html lang="es"><body><p>Fixture YouTube</p></body></html>',
    });
  });

  await page.route('https://www.youtube.com/iframe_api', async (route) => {
    apiRequests += 1;

    if (failApi) {
      await route.abort('failed');
      return;
    }

    await route.fulfill({
      status: 200,
      contentType: 'application/javascript',
      body: iframeApi,
    });
  });

  return {
    embedRequests: () => embedRequests,
    apiRequests: () => apiRequests,
  };
}

async function seek(page: Page, seconds: number) {
  await page.evaluate((value) => {
    const target = window as typeof window & { __eduSeek?: (seconds: number) => void };
    target.__eduSeek?.(value);
  }, seconds);
}

test.describe('BL-MVP-060 · reproductor educativo y karaoke accesible', () => {
  test('muestra contenido propio antes de YouTube y activa línea/token sin mover foco', async ({
    page,
  }) => {
    await mockPublishedSong(page);
    await mockYoutube(page);

    await page.goto(`/aprender/${slug}`);

    const karaoke = page.locator('[data-educational-karaoke]');
    await expect(
      page.locator('[data-karaoke-line="0:1"] .educational-karaoke__japanese'),
    ).toContainText('\u602a\u7363');
    await expect(
      page.locator('[data-karaoke-line="0:1"] .educational-karaoke__japanese'),
    ).toContainText('\u3067\u3059');
    await expect(karaoke).toContainText('Soy un monstruo.');
    await expect(page.locator('iframe[data-video-id]')).toHaveCount(0);

    const ownBeforeExternal = await page.evaluate(() => {
      const owned = document.querySelector('[data-educational-karaoke]');
      const external = document.querySelector('[data-youtube-adapter]');
      if (!owned || !external) return false;

      return Boolean(owned.compareDocumentPosition(external) & Node.DOCUMENT_POSITION_FOLLOWING);
    });
    expect(ownBeforeExternal).toBe(true);

    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();

    const japaneseToggle = page.getByRole('button', { name: 'Japonés' });
    await japaneseToggle.focus();
    await seek(page, 1.2);

    const firstLine = page.locator('[data-karaoke-line="0:1"]');
    await expect(firstLine).toHaveAttribute('data-active', 'true', { timeout: 300 });
    await expect(firstLine.locator('[data-karaoke-token="1"]')).toHaveAttribute(
      'data-active',
      'true',
      { timeout: 300 },
    );
    await expect(japaneseToggle).toBeFocused();

    await seek(page, 2.8);
    const secondLine = page.locator('[data-karaoke-line="0:2"]');
    await expect(secondLine).toHaveAttribute('data-active', 'true', { timeout: 300 });
    await expect(secondLine.locator('[data-karaoke-token][data-active="true"]')).toHaveCount(0);
  });

  test('si YouTube falla conserva letra, traducción y ayudas propias', async ({ page }) => {
    await mockPublishedSong(page);
    await mockYoutube(page, true);

    await page.goto(`/aprender/${slug}`);
    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();

    await expect(page.getByText('YouTube no está disponible')).toBeVisible();
    await expect(
      page.locator('[data-karaoke-line="0:1"] .educational-karaoke__japanese'),
    ).toContainText('\u602a\u7363');
    await expect(
      page.locator('[data-karaoke-line="0:1"] .educational-karaoke__japanese'),
    ).toContainText('\u3067\u3059');
    await expect(page.locator('[data-educational-karaoke]')).toContainText('Soy un monstruo.');
    await expect(page.locator('[data-karaoke-line="0:1"] ruby')).toContainText('怪獣');
  });
});

test.describe('BL-MVP-063 · capas japonés, furigana, romaji y español', () => {
  test('usa lang=ja y ruby/rt; las capas cambian sin reiniciar el reproductor', async ({
    page,
  }) => {
    await mockPublishedSong(page);
    const youtube = await mockYoutube(page);

    await page.goto(`/aprender/${slug}`);

    await expect(page.locator('[data-karaoke-line="0:1"] [lang="ja"]').first()).toContainText(
      '怪獣',
    );
    await expect(page.locator('[data-karaoke-line="0:1"] ruby')).toContainText('怪獣');
    await expect(page.locator('[data-karaoke-line="0:1"] rt')).toHaveText('かいじゅう');
    await expect(page.locator('[data-karaoke-line="0:1"] [data-layer="romaji"]')).toContainText(
      'kaijū desu',
    );
    await expect(
      page.locator('[data-karaoke-line="0:1"] [data-layer="translation"]'),
    ).toContainText('Soy un monstruo.');

    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();
    await seek(page, 1.2);

    const furiganaToggle = page.getByRole('button', { name: 'Furigana' });
    await furiganaToggle.click();
    await expect(furiganaToggle).toHaveAttribute('aria-pressed', 'false');
    await expect(page.locator('[data-karaoke-line="0:1"] ruby')).toHaveCount(0);

    const spanishToggle = page.getByRole('button', { name: 'Español' });
    await spanishToggle.click();
    await expect(page.locator('[data-layer="translation"]')).toHaveCount(0);
    await spanishToggle.click();
    await expect(page.locator('[data-layer="translation"]').first()).toBeVisible();

    expect(youtube.embedRequests()).toBe(1);
    expect(youtube.apiRequests()).toBe(1);

    const currentTime = await page.evaluate(() => {
      const target = window as typeof window & { __eduCurrent?: () => number };
      return target.__eduCurrent?.() ?? -1;
    });
    expect(currentTime).toBeCloseTo(1.2, 3);
    await expect(page.locator('[data-karaoke-line="0:1"]')).toHaveAttribute('data-active', 'true');
  });

  test('mantiene capas accesibles y sin overflow a 320 px', async ({ page }) => {
    await mockPublishedSong(page);
    await mockYoutube(page);

    await page.setViewportSize({ width: 320, height: 1000 });
    await page.goto(`/aprender/${slug}`);

    await expect(
      page.getByRole('heading', { level: 1, name: 'Reproductor educativo' }),
    ).toBeVisible();

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    for (const layer of ['Japonés', 'Furigana', 'Romaji', 'Español']) {
      await expect(page.getByRole('button', { name: layer })).toBeVisible();
    }
  });
});
