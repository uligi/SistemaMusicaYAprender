import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const repoRoot = process.cwd();
const evidenceRoot = join(repoRoot, 'artifacts/e2e');
const screenshotsRoot = join(evidenceRoot, 'screenshots');
const axeRoot = join(evidenceRoot, 'axe');
const axeTags = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'] as const;

async function assertNoHorizontalPageOverflow(page: Page): Promise<void> {
  const metrics = await page.evaluate(() => ({
    innerWidth: window.innerWidth,
    htmlScrollWidth: document.documentElement.scrollWidth,
    bodyScrollWidth: document.body.scrollWidth,
  }));

  expect(metrics.innerWidth).toBe(320);
  expect(
    metrics.htmlScrollWidth,
    'El documento no debe desbordar horizontalmente a 320 px.',
  ).toBeLessThanOrEqual(metrics.innerWidth + 1);
  expect(
    metrics.bodyScrollWidth,
    'El body no debe desbordar horizontalmente a 320 px.',
  ).toBeLessThanOrEqual(metrics.innerWidth + 1);
}

async function assertFocusVisible(locator: Locator): Promise<void> {
  await expect(locator).toBeFocused();
  expect(
    await locator.evaluate((element) => element.matches(':focus-visible')),
    'El elemento alcanzado por teclado debe conservar foco visible.',
  ).toBe(true);
}

async function captureState(page: Page, testInfo: TestInfo, name: string): Promise<void> {
  const screenshotPath = join(screenshotsRoot, `${name}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  await testInfo.attach(`captura-${name}`, {
    path: screenshotPath,
    contentType: 'image/png',
  });
}

async function auditAccessibility(page: Page, testInfo: TestInfo, name: string): Promise<void> {
  const results = await new AxeBuilder({ page }).withTags([...axeTags]).analyze();
  const evidencePath = join(axeRoot, `${name}.json`);
  const evidence = {
    url: results.url,
    timestamp: results.timestamp,
    testEngine: results.testEngine,
    testEnvironment: results.testEnvironment,
    tags: axeTags,
    violations: results.violations,
    incomplete: results.incomplete,
    passes: results.passes.length,
    inapplicable: results.inapplicable.length,
  };

  await writeFile(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8');
  await testInfo.attach(`axe-${name}`, {
    path: evidencePath,
    contentType: 'application/json',
  });

  const summary = results.violations
    .map((violation) => `${violation.id}: ${violation.help} (${violation.nodes.length} nodos)`)
    .join('\n');
  expect(
    results.violations,
    summary || 'Sin violaciones WCAG automatizables detectadas por axe.',
  ).toEqual([]);
}

test.beforeAll(async () => {
  await Promise.all([
    mkdir(screenshotsRoot, { recursive: true }),
    mkdir(axeRoot, { recursive: true }),
  ]);
});

test.describe('BL-MVP-022 · navegación base, teclado, axe y evidencia visual', () => {
  test('navega por teclado a 320 px sin desbordamiento y conserva semántica japonesa', async ({
    page,
  }, testInfo) => {
    await page.goto('/');

    await expect(page.locator('[data-route-id="UI-MVP-001"]')).toBeVisible();
    await expect(page.getByRole('heading', { level: 1, name: 'Inicio' })).toBeFocused();
    await expect(page.locator('[lang="ja"]')).toContainText('音楽で日本語を学ぶ');
    await assertNoHorizontalPageOverflow(page);
    await auditAccessibility(page, testInfo, 'home-320');
    await captureState(page, testInfo, 'home-320');

    await page.keyboard.press('Shift+Tab');
    await assertFocusVisible(page.getByRole('link', { name: 'Acceso', exact: true }));

    await page.keyboard.press('Shift+Tab');
    await assertFocusVisible(page.getByRole('link', { name: 'Registro', exact: true }));

    await page.keyboard.press('Shift+Tab');
    const songsLink = page.getByRole('link', { name: 'Canciones', exact: true });
    await assertFocusVisible(songsLink);
    await captureState(page, testInfo, 'keyboard-focus-canciones-320');

    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(/\/canciones$/);
    await expect(page.locator('[data-route-id="UI-MVP-002"]')).toBeVisible();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Catálogo de canciones' }),
    ).toBeFocused();
    await assertNoHorizontalPageOverflow(page);
    await auditAccessibility(page, testInfo, 'catalog-320');
    await captureState(page, testInfo, 'catalog-320');
  });

  test('captura estados deterministas sin datos manuales', async ({ page }, testInfo) => {
    await page.goto('/preferencias');
    await expect(page.locator('[data-state="UI-EST-07"]')).toBeVisible();
    await expect(page.getByText('Necesitas iniciar sesión')).toBeVisible();
    await assertNoHorizontalPageOverflow(page);
    await auditAccessibility(page, testInfo, 'session-required-320');
    await captureState(page, testInfo, 'session-required-320');

    await page.goto('/esta-ruta-no-existe');
    await expect(page.locator('[data-state="UI-EST-03"]')).toBeVisible();
    await expect(page.getByText('Ruta no disponible')).toBeVisible();
    await assertNoHorizontalPageOverflow(page);
    await auditAccessibility(page, testInfo, 'route-not-found-320');
    await captureState(page, testInfo, 'route-not-found-320');
  });
});

async function mockAnonymousSession(page: Page): Promise<void> {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 401,
      contentType: 'application/problem+json',
      body: JSON.stringify({
        status: 401,
        title: 'Sesión requerida',
        code: 'identity.session.required',
      }),
    });
  });
}

test.describe('BL-MVP-026 · acceso con cookie segura y CSRF', () => {
  test('inicia sesión con teclado, gestor y token antifalsificación efímero', async ({
    page,
  }, testInfo) => {
    const requests: Array<{
      email: string;
      password: string;
      csrf: string;
    }> = [];

    await mockAnonymousSession(page);
    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-e2e-token',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });
    await page.route('**/api/v1/auth/login', async (route) => {
      const request = route.request();
      const payload = request.postDataJSON() as { email: string; password: string };
      requests.push({
        email: payload.email,
        password: payload.password,
        csrf: request.headers()['x-csrf-token'] ?? '',
      });

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'STUDENT',
          message: 'La sesión se inició de forma segura.',
        }),
      });
    });

    await page.goto('/acceso');

    await expect(page.locator('[data-route-id="UI-MVP-007"]')).toBeVisible();
    await expect(page.getByRole('heading', { level: 1, name: 'Inicia sesión' })).toBeFocused();
    const email = page.getByLabel('Correo electrónico');
    const password = page.getByLabel('Contraseña');
    await expect(email).toHaveAttribute('autocomplete', 'username');
    await expect(password).toHaveAttribute('autocomplete', 'current-password');
    await expect(password).toHaveAttribute('type', 'password');
    await assertNoHorizontalPageOverflow(page);
    await auditAccessibility(page, testInfo, 'login-empty-320');

    await page.keyboard.press('Tab');
    await assertFocusVisible(email);
    await email.fill('persona@example.com');
    await page.keyboard.press('Tab');
    await assertFocusVisible(password);
    await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], {
      origin: new URL(page.url()).origin,
    });
    await page.evaluate(async () => navigator.clipboard.writeText('Brisa 日本語 segura 2026'));
    await page.keyboard.press('ControlOrMeta+V');
    await page.keyboard.press('Tab');
    await assertFocusVisible(page.getByRole('button', { name: 'Iniciar sesión' }));
    await page.keyboard.press('Enter');

    await expect(page.locator('[data-state="UI-EST-12"]')).toBeVisible();
    await expect(page.getByText('La sesión se inició de forma segura.')).toBeVisible();
    await expect(email).toHaveValue('persona@example.com');
    await expect(password).toHaveValue('');
    await auditAccessibility(page, testInfo, 'login-authenticated-320');
    await captureState(page, testInfo, 'login-authenticated-320');

    expect(requests).toEqual([
      {
        email: 'persona@example.com',
        password: 'Brisa 日本語 segura 2026',
        csrf: 'csrf-e2e-token',
      },
    ]);
    expect(page.url()).not.toContain('persona@example.com');
    expect(page.url()).not.toContain('csrf-e2e-token');
    expect(
      await page.evaluate(() => ({
        local: Object.keys(localStorage),
        session: Object.keys(sessionStorage),
      })),
    ).toEqual({ local: [], session: [] });
  });

  test('mantiene una respuesta no enumerativa y asocia la corrección al acceso', async ({
    page,
  }, testInfo) => {
    await mockAnonymousSession(page);
    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-invalid-token',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });
    await page.route('**/api/v1/auth/login', async (route) => {
      await route.fulfill({
        status: 401,
        contentType: 'application/problem+json',
        body: JSON.stringify({
          status: 401,
          title: 'No se pudo iniciar sesión',
          code: 'identity.login.failed',
        }),
      });
    });

    await page.goto('/acceso');
    const email = page.getByLabel('Correo electrónico');
    const password = page.getByLabel('Contraseña');
    await email.fill('desconocida@example.com');
    await password.fill('Credencial desconocida 2026');
    await page.getByRole('button', { name: 'Iniciar sesión' }).click();

    await expect(page.locator('[data-state="UI-EST-09"]')).toBeVisible();
    await expect(page.getByText('No se pudo iniciar sesión')).toBeVisible();
    await expect(page.getByText('Revisa el correo y la contraseña')).toBeVisible();
    await expect(email).toHaveValue('desconocida@example.com');
    await expect(password).toHaveValue('');
    await expect(password).toBeFocused();
    await auditAccessibility(page, testInfo, 'login-rejected-320');
  });

  test('bloquea localmente un correo inválido sin enviar credenciales', async ({ page }) => {
    let csrfRequests = 0;
    let loginRequests = 0;
    await mockAnonymousSession(page);
    await page.route('**/api/v1/auth/csrf', async (route) => {
      csrfRequests += 1;
      await route.abort();
    });
    await page.route('**/api/v1/auth/login', async (route) => {
      loginRequests += 1;
      await route.abort();
    });

    await page.goto('/acceso');
    const email = page.getByLabel('Correo electrónico');
    await email.fill('correo-invalido');
    await page.getByLabel('Contraseña').fill('Brisa 日本語 segura 2026');
    await page.getByRole('button', { name: 'Iniciar sesión' }).click();

    await expect(email).toBeFocused();
    await expect(email).toHaveAttribute('aria-invalid', 'true');
    await expect(page.getByText('Escribe una dirección de correo válida.')).toBeVisible();
    expect(csrfRequests).toBe(0);
    expect(loginRequests).toBe(0);
  });
});

async function mockRegistrationConsentCatalog(page: Page): Promise<void> {
  await page.route('**/api/v1/auth/registration-consents', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        notices: [
          {
            purposeCode: 'TERMS_OF_USE',
            title: 'Términos de uso',
            noticeVersion: '2026-08-10',
            effectiveFromUtc: '2026-08-10T00:00:00+00:00',
            required: true,
          },
          {
            purposeCode: 'PRIVACY_POLICY',
            title: 'Política de privacidad',
            noticeVersion: '2026-08-10',
            effectiveFromUtc: '2026-08-10T00:00:00+00:00',
            required: true,
          },
        ],
      }),
    });
  });
}

test.describe('BL-MVP-028 · registro con credencial larga y Argon2id', () => {
  test('completa el formulario con teclado y conserva una respuesta genérica', async ({
    page,
  }, testInfo) => {
    const requests: Array<{
      email: string;
      passwordLength: number;
      consents: Array<{ purposeCode: string; noticeVersion: string; decision: boolean }>;
      idempotencyKey: string;
    }> = [];

    await mockRegistrationConsentCatalog(page);

    await page.route('**/api/v1/auth/register', async (route) => {
      const request = route.request();
      const payload = request.postDataJSON() as {
        email: string;
        password: string;
        consents: Array<{ purposeCode: string; noticeVersion: string; decision: boolean }>;
      };
      requests.push({
        email: payload.email,
        passwordLength: Array.from(payload.password.normalize('NFC')).length,
        consents: payload.consents,
        idempotencyKey: request.headers()['idempotency-key'] ?? '',
      });

      await route.fulfill({
        status: 202,
        contentType: 'application/json',
        headers: { 'x-correlation-id': 'e2e-registration-correlation' },
        body: JSON.stringify({
          status: 'RECEIVED',
          message:
            'La solicitud fue recibida. El resultado no confirma si el correo ya estaba registrado.',
        }),
      });
    });

    await page.goto('/registro');

    await expect(page.locator('[data-route-id="UI-MVP-005"]')).toBeVisible();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Crea tu cuenta personal' }),
    ).toBeFocused();
    await expect(page.getByLabel('Correo electrónico')).toHaveAttribute('autocomplete', 'email');
    const password = page.getByLabel('Contraseña');
    await expect(password).toHaveAttribute('autocomplete', 'new-password');
    await expect(password).toHaveAttribute('type', 'password');
    const terms = page.locator('#registration-consent-terms_of_use');
    const privacy = page.locator('#registration-consent-privacy_policy');
    await expect(terms).toBeVisible();
    await expect(privacy).toBeVisible();
    await expect(terms).toHaveAccessibleName(/Acepto términos de uso.*2026-08-10/i);
    await expect(privacy).toHaveAccessibleName(/Acepto política de privacidad.*2026-08-10/i);
    await assertNoHorizontalPageOverflow(page);
    await auditAccessibility(page, testInfo, 'registration-empty-320');

    await page.keyboard.press('Tab');
    const email = page.getByLabel('Correo electrónico');
    await assertFocusVisible(email);
    await email.fill('persona@example.com');
    await page.keyboard.press('Tab');
    await assertFocusVisible(password);
    await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], {
      origin: new URL(page.url()).origin,
    });
    await page.evaluate(async () => navigator.clipboard.writeText('Brisa 日本語 segura 2026'));
    await page.keyboard.press('ControlOrMeta+V');
    await expect(password).toHaveValue('Brisa 日本語 segura 2026');
    await page.keyboard.press('Tab');
    await assertFocusVisible(terms);
    await page.keyboard.press('Space');
    await page.keyboard.press('Tab');
    await assertFocusVisible(privacy);
    await page.keyboard.press('Space');
    await page.keyboard.press('Tab');
    await assertFocusVisible(page.getByRole('button', { name: 'Continuar registro' }));
    await page.keyboard.press('Enter');

    await expect(page.locator('[data-state="UI-EST-12"]')).toBeVisible();
    await expect(
      page.getByText('El resultado no confirma si el correo ya estaba registrado.'),
    ).toBeVisible();
    await expect(email).toHaveValue('');
    await expect(password).toHaveValue('');
    await expect(terms).not.toBeChecked();
    await expect(privacy).not.toBeChecked();
    await auditAccessibility(page, testInfo, 'registration-accepted-320');
    await captureState(page, testInfo, 'registration-accepted-320');

    await email.fill('persona@example.com');
    await password.fill('Brisa 日本語 segura 2026');
    await terms.check();
    await privacy.check();
    await page.getByRole('button', { name: 'Continuar registro' }).click();
    await expect(page.locator('[data-state="UI-EST-12"]')).toBeVisible();

    expect(requests).toHaveLength(2);
    expect(requests[0]?.email).toBe(requests[1]?.email);
    expect(requests[0]?.passwordLength).toBe(21);
    expect(requests[1]?.passwordLength).toBe(requests[0]?.passwordLength);
    expect(requests[0]?.consents).toEqual([
      { purposeCode: 'TERMS_OF_USE', noticeVersion: '2026-08-10', decision: true },
      { purposeCode: 'PRIVACY_POLICY', noticeVersion: '2026-08-10', decision: true },
    ]);
    expect(requests[1]?.consents).toEqual(requests[0]?.consents);
    expect(requests[0]?.idempotencyKey).toMatch(/^[0-9a-f-]{36}$/);
    expect(requests[1]?.idempotencyKey).toMatch(/^[0-9a-f-]{36}$/);
    expect(requests[0]?.idempotencyKey).not.toBe(requests[1]?.idempotencyKey);
  });

  test('asocia el error local con el campo y no envía datos inválidos', async ({
    page,
  }, testInfo) => {
    let requestCount = 0;
    await mockRegistrationConsentCatalog(page);
    await page.route('**/api/v1/auth/register', async (route) => {
      requestCount += 1;
      await route.abort();
    });

    await page.goto('/registro');
    const email = page.getByLabel('Correo electrónico');
    await email.fill('correo-invalido');
    await page.getByLabel('Contraseña').fill('Brisa 日本語 segura 2026');
    await page.getByRole('button', { name: 'Continuar registro' }).click();

    await expect(email).toBeFocused();
    await expect(email).toHaveAttribute('aria-invalid', 'true');
    await expect(page.getByText('Escribe una dirección de correo válida')).toBeVisible();
    expect(requestCount).toBe(0);
    await auditAccessibility(page, testInfo, 'registration-invalid-320');
  });

  test('asocia la longitud inválida con contraseña y conserva el correo', async ({
    page,
  }, testInfo) => {
    let requestCount = 0;
    await mockRegistrationConsentCatalog(page);
    await page.route('**/api/v1/auth/register', async (route) => {
      requestCount += 1;
      await route.abort();
    });

    await page.goto('/registro');
    const email = page.getByLabel('Correo electrónico');
    const password = page.getByLabel('Contraseña');
    await email.fill('persona@example.com');
    await password.fill('muy-corta');
    await page.getByRole('button', { name: 'Continuar registro' }).click();

    await expect(password).toBeFocused();
    await expect(password).toHaveAttribute('aria-invalid', 'true');
    await expect(page.getByText('Usa una contraseña de 15 a 128 caracteres.')).toBeVisible();
    await expect(email).toHaveValue('persona@example.com');
    expect(requestCount).toBe(0);
    await auditAccessibility(page, testInfo, 'registration-password-invalid-320');
  });

  test('bloquea localmente una aceptación ausente y conserva los datos', async ({
    page,
  }, testInfo) => {
    let requestCount = 0;
    await mockRegistrationConsentCatalog(page);
    await page.route('**/api/v1/auth/register', async (route) => {
      requestCount += 1;
      await route.abort();
    });

    await page.goto('/registro');
    const email = page.getByLabel('Correo electrónico');
    const terms = page.getByRole('checkbox', { name: /Acepto términos de uso/i });
    await email.fill('persona@example.com');
    await page.getByLabel('Contraseña').fill('Brisa 日本語 segura 2026');
    await page.getByRole('button', { name: 'Continuar registro' }).click();

    await expect(terms).toBeFocused();
    await expect(page.getByText('Acepta las versiones vigentes')).toBeVisible();
    await expect(email).toHaveValue('persona@example.com');
    expect(requestCount).toBe(0);
    await auditAccessibility(page, testInfo, 'registration-consent-required-320');
  });
});

test.describe('BL-MVP-025 · verificación de cuenta con token de un uso', () => {
  test('verifica con teclado sin exponer el código en URL ni almacenamiento', async ({
    page,
  }, testInfo) => {
    const verificationCode = 'codigo-de-prueba-no-secreto';
    let submittedToken = '';

    await page.route('**/api/v1/auth/verify-account', async (route) => {
      submittedToken = (route.request().postDataJSON() as { token: string }).token;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'VERIFIED',
          message: 'La cuenta quedó verificada. El código no puede activar la cuenta nuevamente.',
        }),
      });
    });

    await page.goto('/verificar-cuenta');
    await expect(page.locator('[data-route-id="UI-MVP-006"]')).toBeVisible();
    await expect(page).toHaveURL(/\/verificar-cuenta$/);
    await expect(page.getByRole('heading', { level: 1, name: 'Verifica tu cuenta' })).toBeFocused();
    await expect(page.getByLabel('Código recibido')).toHaveAttribute(
      'autocomplete',
      'one-time-code',
    );
    await assertNoHorizontalPageOverflow(page);
    await auditAccessibility(page, testInfo, 'account-verification-empty-320');

    await page.keyboard.press('Tab');
    const tokenInput = page.getByLabel('Código recibido');
    await assertFocusVisible(tokenInput);
    await tokenInput.fill(verificationCode);
    await page.keyboard.press('Tab');
    await assertFocusVisible(page.getByRole('button', { name: 'Verificar cuenta' }));
    await page.keyboard.press('Enter');

    await expect(page.locator('[data-state="UI-EST-12"]')).toContainText('Cuenta verificada');
    await expect(tokenInput).toHaveValue('');
    await expect(page).toHaveURL(/\/verificar-cuenta$/);
    expect(submittedToken).toBe(verificationCode);
    expect(await page.evaluate(() => localStorage.length)).toBe(0);
    expect(await page.evaluate(() => sessionStorage.length)).toBe(0);
    await auditAccessibility(page, testInfo, 'account-verification-accepted-320');
    await captureState(page, testInfo, 'account-verification-accepted-320');
  });

  test('asocia un código inválido con su campo y conserva la corrección accesible', async ({
    page,
  }, testInfo) => {
    await page.route('**/api/v1/auth/verify-account', async (route) => {
      await route.fulfill({
        status: 400,
        contentType: 'application/problem+json',
        body: JSON.stringify({
          type: 'about:blank',
          title: 'No pudimos verificar la cuenta',
          status: 400,
          detail: 'Solicita un código nuevo e inténtalo otra vez.',
          code: 'identity.verification.invalid',
          errors: { token: ['El código no es válido o ya venció. Solicita uno nuevo.'] },
        }),
      });
    });

    await page.goto('/verificar-cuenta');
    const tokenInput = page.getByLabel('Código recibido');
    await tokenInput.fill('codigo-invalido');
    await page.getByRole('button', { name: 'Verificar cuenta' }).click();

    await expect(tokenInput).toBeFocused();
    await expect(tokenInput).toHaveAttribute('aria-invalid', 'true');
    await expect(tokenInput).toHaveValue('codigo-invalido');
    await expect(page.getByText(/no es válido, ya fue consumido o venció/i)).toBeVisible();
    await auditAccessibility(page, testInfo, 'account-verification-invalid-320');
  });

  test('reenvía con respuesta no enumerable e idempotencia por operación', async ({ page }) => {
    const requests: Array<{ email: string; idempotencyKey: string }> = [];
    await page.route('**/api/v1/auth/verification/resend', async (route) => {
      const request = route.request();
      requests.push({
        email: (request.postDataJSON() as { email: string }).email,
        idempotencyKey: request.headers()['idempotency-key'] ?? '',
      });
      await route.fulfill({
        status: 202,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'RECEIVED',
          message: 'Si existe una cuenta pendiente para ese correo, enviaremos un código nuevo.',
        }),
      });
    });

    await page.goto('/verificar-cuenta');
    const email = page.getByLabel('Correo electrónico');
    await email.fill('persona@example.com');
    await page.getByRole('button', { name: 'Solicitar otro código' }).click();
    await expect(page.getByText(/Si existe una cuenta pendiente/i)).toBeVisible();

    await email.fill('otra-persona@example.com');
    await page.getByRole('button', { name: 'Solicitar otro código' }).click();
    await expect(page.getByText(/Si existe una cuenta pendiente/i)).toBeVisible();

    expect(requests).toHaveLength(2);
    expect(requests[0]?.idempotencyKey).toMatch(/^[0-9a-f-]{36}$/);
    expect(requests[1]?.idempotencyKey).toMatch(/^[0-9a-f-]{36}$/);
    expect(requests[0]?.idempotencyKey).not.toBe(requests[1]?.idempotencyKey);
  });
});
