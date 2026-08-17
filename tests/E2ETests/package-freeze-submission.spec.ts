import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const recordingId = '11111111-1111-7111-8111-111111111111';
const packageId = '88888888-8888-7888-8888-888888888888';
const submissionId = '99999999-9999-7999-8999-999999999999';
const lyricsId = '22222222-2222-7222-8222-222222222222';
const timingId = '33333333-3333-7333-8333-333333333333';
const translationId = '44444444-4444-7444-8444-444444444444';
const analysisId = '55555555-5555-7555-8555-555555555555';
const exerciseId = '66666666-6666-7666-8666-666666666666';

async function mockSession(page: Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'EDITOR',
        roles: ['EDITOR', 'REVIEWER'],
        capabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.SUBMIT', 'EDITORIAL.REVIEW'],
      }),
    });
  });
}

async function mockCsrf(page: Page) {
  await page.route('**/api/v1/auth/csrf', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        requestToken: 'csrf-bl048',
        headerName: 'x-csrf-token',
      }),
    });
  });
}

function candidate(
  componentKind: string,
  revisionId: string,
  sourceLyricsRevisionId: string,
  label: string,
) {
  return {
    componentKind,
    revisionId,
    revisionNo: 1,
    statusCode: 'DRAFT',
    checksumSha256: 'ab'.repeat(32),
    sourceLyricsRevisionId,
    label,
    preview:
      componentKind === 'EXERCISE'
        ? '何度でも — Completa el espacio con la opción correcta.'
        : null,
    eligible: true,
    issues: [],
  };
}

function noSubmission() {
  return {
    recordingId,
    exists: false,
    packageId: null,
    packageNo: null,
    packageStatusCode: null,
    packageVersion: 0,
    packageChecksumSha256: null,
    frozenAt: null,
    submissionId: null,
    submissionStatusCode: null,
    submittedAt: null,
    checklistVersion: null,
    eTag: `"submission-${recordingId.replaceAll('-', '')}-none"`,
    message: 'Todavía no existe un paquete sometido a revisión.',
  };
}

function submittedSnapshot() {
  return {
    recordingId,
    exists: true,
    packageId,
    packageNo: 1,
    packageStatusCode: 'SUBMITTED',
    packageVersion: 2,
    packageChecksumSha256: 'cd'.repeat(32),
    frozenAt: '2026-08-18T18:30:00Z',
    submissionId,
    submissionStatusCode: 'SUBMITTED',
    submittedAt: '2026-08-18T18:30:00Z',
    checklistVersion: 'BL-MVP-048.v1',
    eTag: `"submission-${submissionId.replaceAll('-', '')}-package-v2"`,
    message:
      'Paquete 1 congelado y sometido a revisión. La publicación sigue pendiente de BL-MVP-049/050.',
  };
}

function candidates() {
  return [
    candidate('LYRICS', lyricsId, lyricsId, 'Letra · revisión 1'),
    candidate('TIMING', timingId, lyricsId, 'Sincronización · revisión 1'),
    candidate('TRANSLATION', translationId, lyricsId, 'Traducción es · revisión 1'),
    candidate('ANALYSIS', analysisId, lyricsId, 'Análisis · revisión 1'),
    candidate('EXERCISE', exerciseId, lyricsId, 'Ejercicio · revisión 1'),
  ];
}

function readySnapshot() {
  return {
    recordingId,
    catalogVersion: 7,
    packageId,
    packageNo: 1,
    statusCode: 'DRAFT',
    version: 1,
    checksumSha256: 'cd'.repeat(32),
    eTag: '"package-v1"',
    selection: {
      lyricsRevisionId: lyricsId,
      timingRevisionId: timingId,
      translationRevisionId: translationId,
      analysisRevisionId: analysisId,
      exerciseRevisionIds: [exerciseId],
    },
    candidates: candidates(),
    checklist: {
      hasLyrics: true,
      hasTiming: true,
      hasTranslation: true,
      hasAnalysis: true,
      hasExercise: true,
      sourcesCompatible: true,
      exercisesEligible: true,
      hasActiveRights: true,
      hasBrokenLinks: false,
      packageChecksumCurrent: true,
      readyForFreeze: true,
      issues: [],
    },
    message: 'Paquete compatible guardado. Ya puede congelarse y someterse a revisión.',
    latestSubmission: noSubmission(),
  };
}

function freshSnapshotAfterSubmission() {
  return {
    recordingId,
    catalogVersion: 7,
    packageId: null,
    packageNo: null,
    statusCode: 'NOT_CREATED',
    version: 0,
    checksumSha256: null,
    eTag: `"package-${recordingId.replaceAll('-', '')}-none"`,
    selection: {
      lyricsRevisionId: null,
      timingRevisionId: null,
      translationRevisionId: null,
      analysisRevisionId: null,
      exerciseRevisionIds: [],
    },
    candidates: candidates(),
    checklist: {
      hasLyrics: false,
      hasTiming: false,
      hasTranslation: false,
      hasAnalysis: false,
      hasExercise: false,
      sourcesCompatible: false,
      exercisesEligible: false,
      hasActiveRights: true,
      hasBrokenLinks: false,
      packageChecksumCurrent: true,
      readyForFreeze: false,
      issues: ['Selecciona una revisión exacta de letra.'],
    },
    message:
      'El paquete anterior quedó congelado. Una nueva selección se guardará como otro DRAFT.',
    latestSubmission: submittedSnapshot(),
  };
}

test.describe('BL-MVP-048 · congelar y someter paquete', () => {
  test.beforeEach(async ({ page }) => {
    await mockSession(page);
    await mockCsrf(page);
  });

  test('congela con CSRF + If-Match, registra sometimiento y deja un DRAFT nuevo separado', async ({
    page,
  }) => {
    let submitted = false;
    let writes = 0;
    let payload: Record<string, unknown> | null = null;

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package`,
      async (route) => {
        await route.fulfill({
          status: 200,
          headers: {
            etag: submitted ? freshSnapshotAfterSubmission().eTag : readySnapshot().eTag,
          },
          contentType: 'application/json',
          body: JSON.stringify(submitted ? freshSnapshotAfterSubmission() : readySnapshot()),
        });
      },
    );

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package/submit`,
      async (route) => {
        writes += 1;
        expect(route.request().headers()['if-match']).toBe('"package-v1"');
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl048');
        payload = route.request().postDataJSON() as Record<string, unknown>;
        submitted = true;

        await route.fulfill({
          status: 200,
          headers: { etag: submittedSnapshot().eTag },
          contentType: 'application/json',
          body: JSON.stringify(submittedSnapshot()),
        });
      },
    );

    await page.goto(`/editorial/paquetes/${recordingId}`);
    await expect(page.getByRole('heading', { name: 'Compatible para congelar' })).toBeVisible();

    await page
      .getByLabel('Motivo del sometimiento')
      .fill('Checklist completo y componentes exactos revisados.');
    await page.getByRole('button', { name: 'Congelar y someter a revisión' }).click();

    await expect(page.getByRole('heading', { name: 'Paquete 1 sometido' })).toBeVisible();
    await expect(page.getByText('BL-MVP-048.v1')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Nuevo paquete' })).toBeVisible();
    await expect(page.getByText(/nueva selección se guardará como otro DRAFT/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /publicar/i })).toHaveCount(0);

    expect(writes).toBe(1);
    expect(payload).toEqual({
      reason: 'Checklist completo y componentes exactos revisados.',
    });
  });

  test('un cambio concurrente bloquea la congelación y conserva la selección visible', async ({
    page,
  }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package`,
      async (route) => {
        await route.fulfill({
          status: 200,
          headers: { etag: readySnapshot().eTag },
          contentType: 'application/json',
          body: JSON.stringify(readySnapshot()),
        });
      },
    );

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package/submit`,
      async (route) => {
        await route.fulfill({
          status: 412,
          contentType: 'application/problem+json',
          body: JSON.stringify({
            title: 'El paquete cambió antes de congelarse',
            detail: 'El paquete DRAFT cambió. Recarga y confirma nuevamente antes de congelar.',
            status: 412,
            code: 'editorial.package.submit.source-changed',
          }),
        });
      },
    );

    await page.goto(`/editorial/paquetes/${recordingId}`);
    await page.getByLabel('Motivo del sometimiento').fill('Confirmar sin perder selección.');
    await page.getByRole('button', { name: 'Congelar y someter a revisión' }).click();

    await expect(page.getByText('Hay una versión más reciente')).toBeVisible();
    await expect(page.getByLabel('Letra exacta')).toHaveValue(lyricsId);
    await expect(page.getByLabel('Traducción')).toHaveValue(translationId);
    await expect(page.getByRole('heading', { name: 'Compatible para congelar' })).toBeVisible();
  });

  test('Paquete y revisión se descubre desde la navegación contextual de la canción', async ({
    page,
  }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/exercise-bank`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            recordingId,
            exerciseCount: 0,
            exercises: [],
          }),
        });
      },
    );

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package`,
      async (route) => {
        await route.fulfill({
          status: 200,
          headers: { etag: freshSnapshotAfterSubmission().eTag },
          contentType: 'application/json',
          body: JSON.stringify(freshSnapshotAfterSubmission()),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);

    const packageLink = page.getByRole('link', { name: 'Paquete y revisión' });
    await expect(packageLink).toBeVisible();
    await packageLink.click();

    await expect(page).toHaveURL(`/editorial/paquetes/${recordingId}`);
    await expect(page.getByRole('heading', { name: 'Paquete educativo compatible' })).toBeVisible();
    await expect(packageLink).toHaveAttribute('aria-current', 'page');
  });

  test('UI-MVP-026 aprovecha escritorio y conserva teclado, axe y 320 px sin overflow', async ({
    page,
  }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package`,
      async (route) => {
        await route.fulfill({
          status: 200,
          headers: { etag: readySnapshot().eTag },
          contentType: 'application/json',
          body: JSON.stringify(readySnapshot()),
        });
      },
    );

    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(`/editorial/paquetes/${recordingId}`);

    await expect(page.locator('.compatible-package__workspace')).toBeVisible();
    await expect(page.locator('.compatible-package__sidebar')).toBeVisible();

    const desktop = await page.evaluate(() => {
      const article = document.querySelector<HTMLElement>('[data-route-id="UI-MVP-026"]');
      const workspace = document.querySelector<HTMLElement>('.compatible-package__workspace');
      const form = document.querySelector<HTMLElement>('.compatible-package__form');
      const sidebar = document.querySelector<HTMLElement>('.compatible-package__sidebar');

      if (!article || !workspace || !form || !sidebar) {
        return null;
      }

      const articleRect = article.getBoundingClientRect();
      const formRect = form.getBoundingClientRect();
      const sidebarRect = sidebar.getBoundingClientRect();

      return {
        articleWidth: articleRect.width,
        formLeft: formRect.left,
        formRight: formRect.right,
        sidebarLeft: sidebarRect.left,
        sidebarWidth: sidebarRect.width,
      };
    });

    expect(desktop).not.toBeNull();
    expect(desktop!.articleWidth).toBeGreaterThan(850);
    expect(desktop!.sidebarLeft).toBeGreaterThan(desktop!.formLeft);
    expect(desktop!.formRight).toBeLessThanOrEqual(desktop!.sidebarLeft + 1);
    expect(desktop!.sidebarWidth).toBeGreaterThan(250);

    await page.setViewportSize({ width: 320, height: 900 });
    await page.reload();

    await expect(page.getByRole('heading', { name: 'Paquete educativo compatible' })).toBeFocused();

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });
});
