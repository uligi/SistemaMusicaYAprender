import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '15900000-0000-7000-8000-000000000001';
const lyricsRevisionId = '15900000-0000-7000-8000-000000000002';
const sourceId = '15900000-0000-7000-8000-000000000003';
const videoId = 'a8dgNdJVluc';

const lines = [
  ['15900000-0000-7000-8000-000000000011', 1, '何度でも'],
  ['15900000-0000-7000-8000-000000000012', 2, 'この暗い夜の怪獣になっても'],
  ['15900000-0000-7000-8000-000000000013', 3, 'ここに残しておきたいんだよ'],
] as const;

const context = {
  recordingId,
  lyricsRevisionId,
  lyricsRevisionNo: 2,
  sources: [
    {
      sourceId,
      providerCode: 'YOUTUBE',
      externalRef: videoId,
      durationMs: 290000,
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
    revisionNo: 2,
    parentRevisionId: null,
    statusCode: 'DRAFT',
    createdBy: '15900000-0000-7000-8000-000000000004',
    createdAt: '2026-08-13T00:00:00Z',
    checksumSha256: 'a'.repeat(64),
    version: 2,
    sections: [
      {
        sectionId: '15900000-0000-7000-8000-000000000010',
        sectionType: 'VERSE',
        label: 'Verso 1',
        displayOrder: 0,
        lines: lines.map(([lineId, lineNo, japaneseText]) => ({
          lineId,
          lineNo,
          japaneseText,
          normalizedText: japaneseText,
          speakerLabel: '山口一郎',
          tokens: [],
        })),
      },
    ],
  },
};

const iframeApi = `
(() => {
  let currentTime = 0;
  let currentEvents = null;

  window.__bl059UxSeek = (seconds) => {
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
      body: JSON.stringify(context),
    });
  });

  await page.route('**/api/v1/editorial/song-drafts/*/lyrics-revisions/latest', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(lyrics),
    });
  });

  await page.route('https://www.youtube-nocookie.com/embed/**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'text/html; charset=utf-8',
      body: '<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Fixture</title></head><body><div><p>Fixture neutral.</p></div></body></html>',
    });
  });

  await page.route('https://www.youtube.com/iframe_api', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/javascript', body: iframeApi });
  });
}

async function seek(page: import('@playwright/test').Page, seconds: number) {
  await page.evaluate((value) => {
    const target = window as typeof window & { __bl059UxSeek?: (seconds: number) => void };
    target.__bl059UxSeek?.(value);
  }, seconds);
}

test.describe('BL-MVP-059E · UX del editor de sincronización', () => {
  test('mantiene video sticky a la par y permite temporizar/cambiar línea sin scroll', async ({
    page,
  }) => {
    await mockBase(page);
    await page.setViewportSize({ width: 1366, height: 768 });
    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    const workspace = page.locator('[data-editorial-sync-workspace]');
    await expect(workspace).toBeVisible();

    const routeSurface = page.locator('.route-surface.synchronization-structure');
    const routeBox = await routeSurface.boundingBox();
    expect(routeBox).not.toBeNull();
    expect(routeBox?.width ?? 0).toBeGreaterThan(900);

    const gridColumns = await workspace.evaluate(
      (element) => window.getComputedStyle(element).gridTemplateColumns,
    );
    expect(gridColumns.split(' ').length).toBeGreaterThanOrEqual(2);

    const previewPosition = await page
      .locator('.synchronization-structure__preview-panel')
      .evaluate((element) => window.getComputedStyle(element).position);
    expect(previewPosition).toBe('sticky');

    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();

    await seek(page, 1.25);
    await expect(page.getByLabel('Tiempo de vista previa (ms)')).toHaveValue('1250', {
      timeout: 500,
    });
    await page.getByRole('button', { name: 'Marcar inicio línea 1' }).click();
    await expect(page.getByLabel('Inicio línea 1 (ms)')).toHaveValue('1250');

    const scrollBefore = await page.evaluate(() => window.scrollY);
    await seek(page, 2.4);
    await page.getByRole('button', { name: 'Marcar fin línea 1' }).click();

    await expect(page.getByLabel('Línea que estás editando')).toHaveValue(lines[1][0]);
    await expect(page.getByText(lines[1][2], { exact: true })).toBeVisible();
    const scrollAfter = await page.evaluate(() => window.scrollY);
    expect(Math.abs(scrollAfter - scrollBefore)).toBeLessThanOrEqual(2);

    await page.getByRole('button', { name: 'Línea anterior' }).click();
    await expect(page.getByLabel('Línea que estás editando')).toHaveValue(lines[0][0]);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('en móvil apila video/editor sin overflow y conserva navegación por líneas', async ({
    page,
  }) => {
    await mockBase(page);
    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    await expect(page.getByLabel('Línea que estás editando')).toBeVisible();
    await page.getByLabel('Línea que estás editando').selectOption(lines[2][0]);
    await expect(page.getByText(lines[2][2], { exact: true })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });
});
