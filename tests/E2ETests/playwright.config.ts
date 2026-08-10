import { defineConfig } from '@playwright/test';
import { join } from 'node:path';

const repoRoot = process.cwd();
const configDirectory = join(repoRoot, 'tests/E2ETests');
const externalBaseUrl = process.env.PLAYWRIGHT_TEST_BASE_URL?.trim();
const baseURL = externalBaseUrl || 'http://127.0.0.1:4173';

export default defineConfig({
  testDir: configDirectory,
  testMatch: '**/*.spec.ts',
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  workers: 1,
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  outputDir: join(repoRoot, 'artifacts/test-results/playwright'),
  reporter: [
    ['list'],
    ['html', { outputFolder: join(repoRoot, 'artifacts/e2e/playwright-report'), open: 'never' }],
    ['junit', { outputFile: join(repoRoot, 'artifacts/test-results/e2e.xml') }],
  ],
  use: {
    baseURL,
    viewport: { width: 320, height: 800 },
    locale: 'es-CR',
    timezoneId: 'America/Costa_Rica',
    colorScheme: 'light',
    contextOptions: {
      reducedMotion: 'reduce',
    },
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium-320',
      use: { browserName: 'chromium' },
    },
  ],
  ...(externalBaseUrl
    ? {}
    : {
        webServer: {
          command:
            'npm run preview --workspace @musica-aprender/web -- --host 127.0.0.1 --port 4173',
          url: baseURL,
          reuseExistingServer: !process.env.CI,
          timeout: 120_000,
        },
      }),
});
