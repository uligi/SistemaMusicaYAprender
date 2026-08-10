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
