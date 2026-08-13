import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const slug = 'kaiju-0123456789abcdefabcd';
const videoId = 'a8dgNdJVluc';

const detail = {
  slug,
  canonicalTitle: '怪獣',
  recordingTitle: 'Kaiju',
  recordingDurationMs: 290000,
  artistName: 'サカナクション',
  providerCode: 'YOUTUBE',
  territoryCode: 'CR',
  languageTag: 'es',
  availabilityValidFrom: '2026-08-13T00:00:00Z',
  availabilityValidTo: null,
  availableComponents: ['CATALOG', 'LYRICS', 'TIMING'],
  sourceExternalRef: videoId,
};

async function mockDetail(page: import('@playwright/test').Page) {
  await page.route('**/api/v1/public/catalog/songs/*', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(detail),
    });
  });
}

const mockIframeApi = `
(() => {
  window.YT = {
    Player: function(element, options) {
      const iframe = typeof element === 'string' ? document.getElementById(element) : element;
      if (!iframe) throw new Error('mock-player-element-missing');
      let currentTime = 0;
      this.destroy = () => {};
      this.playVideo = () => options.events.onStateChange({ data: 1 });
      this.pauseVideo = () => options.events.onStateChange({ data: 2 });
      this.seekTo = (seconds) => { currentTime = seconds; };
      this.getCurrentTime = () => currentTime;
      queueMicrotask(() => options.events.onReady({ target: this }));
    }
  };
  window.onYouTubeIframeAPIReady?.();
})();
`;

test.describe('BL-MVP-058 · adaptador aislado YouTube IFrame', () => {
  test('carga YouTube solo tras acción y usa nocookie + origin', async ({ page }) => {
    await mockDetail(page);

    let iframeApiRequests = 0;
    await page.route('https://www.youtube.com/iframe_api', async (route) => {
      iframeApiRequests += 1;
      await route.fulfill({
        status: 200,
        contentType: 'application/javascript',
        body: mockIframeApi,
      });
    });

    await page.goto(`/aprender/${slug}`);

    await expect(page.getByRole('heading', { name: 'Reproductor educativo' })).toBeVisible();
    await expect(page.getByRole('heading', { name: '怪獣' })).toBeVisible();
    expect(iframeApiRequests).toBe(0);
    await expect(page.locator('iframe')).toHaveCount(0);

    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();

    const iframe = page.locator('iframe');
    await expect(iframe).toHaveCount(1);
    expect(iframeApiRequests).toBe(1);

    const source = await iframe.getAttribute('src');
    expect(source).not.toBeNull();
    const parsed = new URL(source!);
    expect(parsed.origin).toBe('https://www.youtube-nocookie.com');
    expect(parsed.pathname).toBe(`/embed/${videoId}`);
    expect(parsed.searchParams.get('enablejsapi')).toBe('1');
    const appOrigin = new URL(page.url()).origin;
    expect(parsed.searchParams.get('origin')).toBe(appOrigin);

    const box = await iframe.boundingBox();
    expect(box).not.toBeNull();
    expect(box!.width).toBeGreaterThanOrEqual(200);
    expect(box!.height).toBeGreaterThanOrEqual(200);

    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();
    await expect(iframe).toHaveAttribute('title', 'Reproductor de YouTube para 怪獣');
    await expect(iframe).toHaveAttribute('referrerpolicy', 'strict-origin-when-cross-origin');

    // El iframe es contenido de un tercero. Auditamos nuestro documento y el elemento iframe,
    // pero no hacemos responsable a la aplicación del DOM interno servido por YouTube.
    const accessibilityScanResults = await new AxeBuilder({ page })
      .options({ iframes: false })
      .analyze();
    expect(accessibilityScanResults.violations).toEqual([]);
  });

  test('bloqueo externo degrada en menos de 2 s y conserva contenido propio', async ({ page }) => {
    await mockDetail(page);

    await page.route('https://www.youtube.com/iframe_api', async (route) => {
      await route.abort('failed');
    });

    await page.goto(`/aprender/${slug}`);
    await expect(page.getByRole('heading', { name: '怪獣' })).toBeVisible();

    const started = Date.now();
    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('YouTube no está disponible')).toBeVisible({ timeout: 2000 });
    expect(Date.now() - started).toBeLessThanOrEqual(2000);

    await expect(page.getByRole('heading', { name: '怪獣' })).toBeVisible();
    await expect(
      page.getByText('Esta información, la letra y las demás capas educativas', { exact: false }),
    ).toBeVisible();
  });

  test('no usa Data API ni carga iframe antes de la decisión', async ({ page }) => {
    await mockDetail(page);

    const forbidden: string[] = [];
    page.on('request', (request) => {
      const url = request.url();
      if (url.includes('googleapis.com/youtube/v3') || url.includes('/youtube/v3/')) {
        forbidden.push(url);
      }
    });

    await page.goto(`/aprender/${slug}`);
    await page.waitForTimeout(250);

    expect(forbidden).toEqual([]);
    await expect(page.locator('script[data-youtube-iframe-api="true"]')).toHaveCount(0);
    await expect(page.locator('iframe')).toHaveCount(0);
  });

  test('mantiene UI-MVP-009 a 320px sin desbordamiento horizontal', async ({ page }) => {
    await mockDetail(page);
    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto(`/aprender/${slug}`);

    await expect(page.getByRole('heading', { name: 'Reproductor educativo' })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });

  test('vista previa editorial del borrador no requiere publicación ni slug público', async ({
    page,
  }) => {
    const draftRecordingId = 'efc89b51-cfa6-5a56-91b1-6bc03942a971';

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
      `**/api/v1/editorial/song-drafts/${draftRecordingId}/synchronization-context`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            recordingId: draftRecordingId,
            lyricsRevisionId: '22222222-2222-7222-8222-222222222222',
            lyricsRevisionNo: 2,
            sources: [
              {
                sourceId: '33333333-3333-7333-8333-333333333333',
                providerCode: 'YOUTUBE',
                externalRef: videoId,
                durationMs: null,
                sourceOffsetMs: 0,
                statusCode: 'DRAFT',
                timingRevision: null,
              },
            ],
          }),
        });
      },
    );

    let publicSongRequests = 0;
    page.on('request', (request) => {
      if (request.url().includes('/api/v1/public/catalog/songs/')) {
        publicSongRequests += 1;
      }
    });

    await page.route('https://www.youtube.com/iframe_api', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/javascript',
        body: mockIframeApi,
      });
    });

    await page.goto(`/editorial/canciones/${draftRecordingId}/sincronizacion`);

    await expect(
      page.getByText('BL-MVP-058 · VISTA PREVIA EDITORIAL · NO PUBLICA', { exact: true }),
    ).toBeVisible();
    await expect(page.getByRole('button', { name: 'Cargar reproductor de YouTube' })).toBeVisible();
    await expect(page.locator('iframe')).toHaveCount(0);
    expect(publicSongRequests).toBe(0);

    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();

    const editorialIframe = page.locator('iframe');
    await expect(editorialIframe).toHaveCount(1);
    await expect(editorialIframe).toHaveAttribute(
      'title',
      `Reproductor de YouTube para Fuente editorial ${videoId}`,
    );
    await expect(editorialIframe).toHaveAttribute(
      'referrerpolicy',
      'strict-origin-when-cross-origin',
    );
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();
    expect(publicSongRequests).toBe(0);

    // YouTube controla el DOM del frame. Axe debe evaluar la superficie propia sin
    // convertir defectos internos del proveedor externo en defectos de nuestra página.
    const accessibility = await new AxeBuilder({ page }).options({ iframes: false }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
