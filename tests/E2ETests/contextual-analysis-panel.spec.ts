import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const slug = 'kaiju-0123456789abcdefabcd';
const tokenKey = 'A1B2C3D4E5F60718293A';
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
      japaneseText: '怪獣になる',
      speakerLabel: null,
      precisionCode: 'TOKEN',
      startMs: 1000,
      endMs: 4000,
      tokens: [
        { tokenNo: 1, surface: '怪獣', startMs: 1000, endMs: 2300 },
        { tokenNo: 2, surface: 'になる', startMs: 2300, endMs: 4000 },
      ],
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
      japaneseText: '怪獣になる',
      speakerLabel: null,
      tokens: [
        {
          tokenNo: 1,
          surface: '怪獣',
          startOffset: 0,
          endOffset: 2,
          analysisKey: tokenKey,
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
          surface: 'になる',
          startOffset: 2,
          endOffset: 5,
          analysisKey: '00112233445566778899',
          readings: [
            {
              readingKana: 'になる',
              furigana: null,
              romaji: 'ni naru',
              readingType: 'CONTEXTUAL',
            },
          ],
        },
      ],
      translations: [
        {
          variantCode: 'NATURAL',
          translatedText: 'Me convierto en un monstruo.',
          displayOrder: 1,
        },
      ],
    },
  ],
};

const analysis = {
  available: true,
  tokenKey,
  surface: '怪獣',
  tokenNo: 1,
  targetLanguage: 'es',
  line: {
    sectionOrder: 0,
    sectionLabel: 'Verso',
    lineNo: 1,
    japaneseText: '怪獣になる',
    speakerLabel: null,
  },
  readings: [
    {
      readingKana: 'かいじゅう',
      furigana: 'かいじゅう',
      romaji: 'kaijū',
      readingType: 'CONTEXTUAL',
    },
  ],
  vocabulary: [
    {
      lemma: '怪獣',
      reading: 'かいじゅう',
      partOfSpeech: 'NOUN',
      senseKey: 'MONSTER',
      inflection: null,
      confidenceCode: 'CONFIRMED',
      senses: [
        {
          languageTag: 'es',
          definition: 'Monstruo o criatura gigantesca.',
          usageNote: 'En la canción funciona como imagen contextual.',
          displayOrder: 1,
        },
      ],
    },
  ],
  kanji: [
    {
      character: '怪',
      charOffset: 0,
      gradeCode: null,
      jlptCode: 'N1',
      readings: [
        {
          reading: 'かい',
          readingType: 'ON',
          languageTag: 'es',
          meaning: 'extraño; sospechoso',
          displayOrder: 1,
        },
      ],
    },
    {
      character: '獣',
      charOffset: 1,
      gradeCode: 'G6',
      jlptCode: 'N1',
      readings: [
        {
          reading: 'じゅう',
          readingType: 'ON',
          languageTag: 'es',
          meaning: 'bestia',
          displayOrder: 1,
        },
      ],
    },
  ],
  morphology: [
    {
      lemma: '怪獣',
      partOfSpeechCode: 'NOUN',
      conjugationCode: null,
    },
  ],
  grammar: [
    {
      grammarCode: 'N-NINARU',
      title: '〜になる',
      levelCode: 'N4',
      note: 'Cambio de estado.',
      explanation: 'Expresa convertirse o llegar a ser algo.',
      examples: null,
    },
  ],
  provenance: [
    {
      sourceType: 'EDITORIAL',
      citation: 'Curaduría interna contrastada',
      locator: 'Línea 1',
      contributionType: 'ANALYSIS',
    },
  ],
};

const iframeApi = `
(() => {
  let currentTime = 2;
  let currentEvents = null;
  window.__analysisPlayerInstances = 0;
  window.__analysisCurrentTime = () => currentTime;

  window.YT = {
    Player: function(element, options) {
      window.__analysisPlayerInstances += 1;
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

async function mockStudent(page: Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 401,
      contentType: 'application/problem+json',
      body: JSON.stringify({ title: 'Sin sesión', status: 401 }),
    });
  });

  await page.route(`**/api/v1/public/catalog/songs/${slug}?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(detail),
    });
  });

  await page.route(`**/api/v1/public/catalog/songs/${slug}/synchronization?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(timeline),
    });
  });

  await page.route(`**/api/v1/public/catalog/songs/${slug}/layers?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(layers),
    });
  });

  await page.route(
    `**/api/v1/public/catalog/songs/${slug}/analysis/${tokenKey}?**`,
    async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(analysis),
      });
    },
  );

  await page.route('https://www.youtube-nocookie.com/embed/**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'text/html; charset=utf-8',
      body: '<!doctype html><html><body><p>Fixture YouTube</p></body></html>',
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

test.describe('BL-MVP-068 · panel de análisis contextual', () => {
  test('seleccionar token abre análisis autorizado sin remontar ni detener el player', async ({
    page,
  }) => {
    await mockStudent(page);
    await page.goto(`/aprender/${slug}`);

    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();

    await expect
      .poll(() =>
        page.evaluate(
          () =>
            (window as typeof window & { __analysisPlayerInstances?: number })
              .__analysisPlayerInstances ?? 0,
        ),
      )
      .toBe(1);

    const before = await page.evaluate(
      () =>
        (
          window as typeof window & { __analysisCurrentTime?: () => number }
        ).__analysisCurrentTime?.() ?? -1,
    );

    await page.getByRole('button', { name: 'Analizar 怪獣' }).click();

    await expect(page.getByText('Monstruo o criatura gigantesca.')).toBeVisible();
    await expect(
      page.locator('.contextual-analysis__selection').getByText('かいじゅう', { exact: true }),
    ).toBeVisible();
    await page.getByText('Gramática de esta línea', { exact: true }).click();
    await expect(page.getByText('〜になる')).toBeVisible();

    await page.getByText('Kanji', { exact: true }).click();
    await expect(page.getByText('bestia')).toBeVisible();

    expect(
      await page.evaluate(
        () =>
          (window as typeof window & { __analysisPlayerInstances?: number })
            .__analysisPlayerInstances ?? 0,
      ),
    ).toBe(1);

    expect(
      await page.evaluate(
        () =>
          (
            window as typeof window & { __analysisCurrentTime?: () => number }
          ).__analysisCurrentTime?.() ?? -1,
      ),
    ).toBe(before);
  });

  test('prioriza contexto, conserva niveles orientativos y no llama servicios lingüísticos externos', async ({
    page,
  }) => {
    const external: string[] = [];
    page.on('request', (request) => {
      const url = new URL(request.url());
      if (
        !['127.0.0.1', 'localhost', 'www.youtube.com', 'www.youtube-nocookie.com'].includes(
          url.hostname,
        )
      ) {
        external.push(request.url());
      }
    });

    await mockStudent(page);
    await page.goto(`/aprender/${slug}`);
    await page.getByRole('button', { name: 'Analizar 怪獣' }).click();

    await expect(page.getByText('Significado en esta canción:', { exact: false })).toBeVisible();
    await page.getByText('Kanji', { exact: true }).click();
    await expect(
      page.getByText('nivel orientativo, no certificación oficial.', { exact: false }),
    ).toHaveCount(2);
    await page.getByText('Gramática de esta línea', { exact: true }).click();
    await expect(page.getByText('Expresa convertirse o llegar a ser algo.')).toBeVisible();

    expect(external).toEqual([]);
  });

  test('UI-MVP-010 abre el mismo análisis por deep link y una referencia incompatible no se sustituye', async ({
    page,
  }) => {
    await mockStudent(page);
    await page.goto(`/aprender/${slug}/analisis/${tokenKey}`);

    await expect(page.locator('[data-route-id="UI-MVP-010"]')).toBeVisible();
    await expect(page.getByText('Monstruo o criatura gigantesca.')).toBeVisible();
    await expect(
      page.getByRole('link', { name: 'Volver al reproductor educativo' }),
    ).toHaveAttribute('href', `/aprender/${slug}`);

    await page.route(
      `**/api/v1/public/catalog/songs/${slug}/analysis/FFFFFFFFFFFFFFFFFFFF?**`,
      async (route) => {
        await route.fulfill({
          status: 409,
          contentType: 'application/problem+json',
          body: JSON.stringify({
            title: 'Análisis contextual incompatible',
            status: 409,
            detail: 'No se mezclará otra revisión.',
            code: 'content.public-analysis.incompatible',
          }),
        });
      },
    );

    await page.goto(`/aprender/${slug}/analisis/FFFFFFFFFFFFFFFFFFFF`);
    await expect(page.getByText('Hay una versión más reciente')).toBeVisible();
    await expect(page.getByText('Monstruo o criatura gigantesca.')).toHaveCount(0);
  });

  test('a 320 px mantiene token, panel y deep link accesibles sin overflow', async ({ page }) => {
    await mockStudent(page);
    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto(`/aprender/${slug}`);
    await page.getByRole('button', { name: 'Analizar 怪獣' }).click();

    await expect(page.locator('[data-contextual-analysis-panel]')).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
