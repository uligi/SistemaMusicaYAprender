import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const slug = 'kaiju-0123456789abcdefabcd';

const song = {
  slug,
  canonicalTitle: '怪獣',
  recordingTitle: '怪獣',
  artistName: 'サカナクション',
  availableComponents: ['LYRICS', 'EXERCISE'],
};

const eligibleContext = {
  eligible: true,
  blockingReason: null,
  eligibleExerciseCount: 2,
  publicationNo: 5,
  activeSession: null,
};

async function mockStudentSession(page: Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'STUDENT',
        roles: ['STUDENT'],
        capabilities: [],
      }),
    });
  });
}

async function mockPageContext(
  page: Page,
  context: typeof eligibleContext | Record<string, unknown> = eligibleContext,
) {
  await mockStudentSession(page);

  await page.route('**/api/v1/public/catalog/songs/*', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(song),
    });
  });

  await page.route('**/api/v1/study/songs/*/session-start**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(context),
    });
  });
}

test.describe('BL-MVP-072 · inicio privado de sesión de estudio', () => {
  test('inicia una única sesión publicada con CSRF e idempotencia sin exponer respuestas', async ({
    page,
  }) => {
    await mockPageContext(page);

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-bl072',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    let writes = 0;
    let idempotencyKey = '';

    await page.route('**/api/v1/study/songs/*/sessions**', async (route) => {
      writes += 1;
      idempotencyKey = route.request().headers()['idempotency-key'] ?? '';

      expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl072');

      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          studySessionId: '17200000-0000-7000-8000-000000000001',
          statusCode: 'ACTIVE',
          startedAt: '2026-08-16T20:00:00Z',
          version: 1,
          publicationNo: 5,
          reusedExisting: false,
          message: 'Tu sesión privada está lista.',
        }),
      });
    });

    await page.goto(`/estudiar/${slug}`);

    await expect(page.locator('[data-route-id="UI-MVP-011"]')).toBeVisible();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Practicar esta canción' }),
    ).toBeFocused();
    await expect(page.getByText('Tu sesión es privada')).toBeVisible();
    await expect(page.getByText('Publicación 5')).toBeVisible();

    await page.getByRole('button', { name: 'Empezar a practicar' }).click();

    await expect(
      page.getByRole('heading', { level: 2, name: 'Tu sesión está preparada' }),
    ).toBeVisible();
    await expect(
      page.getByText(
        'Todavía no se ha registrado ninguna respuesta, nota, evidencia ni cambio de progreso.',
      ),
    ).toBeVisible();

    expect(writes).toBe(1);
    expect(idempotencyKey.length).toBeGreaterThanOrEqual(8);
    await expect(page.getByText(/respuesta correcta/i)).toHaveCount(0);
    await expect(page.getByText(/solución editorial/i)).toHaveCount(0);
  });

  test('sin actividad publicada explica el bloqueo y no crea sesión vacía', async ({ page }) => {
    await mockPageContext(page, {
      eligible: false,
      blockingReason:
        'Todavía no hay una práctica publicada para esta canción. Los borradores editoriales no crean sesiones de estudiante.',
      eligibleExerciseCount: 0,
      publicationNo: 5,
      activeSession: null,
    });

    let writes = 0;
    await page.route('**/api/v1/study/songs/*/sessions**', async (route) => {
      writes += 1;
      await route.abort();
    });

    await page.goto(`/estudiar/${slug}`);

    await expect(
      page.getByRole('heading', {
        name: 'Todavía no hay una práctica publicada',
        exact: true,
      }),
    ).toBeVisible();
    await expect(page.getByRole('button', { name: 'Empezar a practicar' })).toHaveCount(0);
    expect(writes).toBe(0);
  });

  test('una sesión activa se conserva y no ofrece crear una segunda', async ({ page }) => {
    await mockPageContext(page, {
      eligible: true,
      blockingReason: null,
      eligibleExerciseCount: 2,
      publicationNo: 5,
      activeSession: {
        studySessionId: '17200000-0000-7000-8000-000000000001',
        statusCode: 'ACTIVE',
        startedAt: '2026-08-16T20:00:00Z',
        version: 1,
      },
    });

    let writes = 0;
    await page.route('**/api/v1/study/songs/*/sessions**', async (route) => {
      writes += 1;
      await route.abort();
    });

    await page.goto(`/estudiar/${slug}`);

    await expect(page.getByText('Ya tienes una sesión en curso')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Empezar a practicar' })).toHaveCount(0);
    expect(writes).toBe(0);
  });

  test('UI-MVP-011 conserva privacidad, teclado y accesibilidad a 320 px', async ({ page }) => {
    await mockPageContext(page);
    await page.goto(`/estudiar/${slug}`);

    const button = page.getByRole('button', { name: 'Empezar a practicar' });
    await button.focus();
    await expect(button).toBeFocused();

    const metrics = await page.evaluate(() => ({
      innerWidth: window.innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }));

    expect(metrics.innerWidth).toBe(320);
    expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.innerWidth + 1);

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();

    expect(results.violations).toEqual([]);
  });
});
