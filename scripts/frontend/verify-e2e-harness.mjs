import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const repoRoot = process.cwd();
const readUtf8 = (relativePath) => readFile(join(repoRoot, relativePath), 'utf8');

const requiredFiles = [
  'package.json',
  'package-lock.json',
  'tests/E2ETests/playwright.config.ts',
  'tests/E2ETests/tsconfig.json',
  'tests/E2ETests/base-accessibility.spec.ts',
  'tests/E2ETests/README.md',
  'docs/engineering/frontend/e2e-accessibility-visual.md',
  '.github/workflows/ci.yml',
  'scripts/check-quality.ps1',
];

for (const relativePath of requiredFiles) {
  await assert.doesNotReject(() => readUtf8(relativePath), `Falta ${relativePath}`);
}

const packageJson = JSON.parse(await readUtf8('package.json'));
const packageLock = JSON.parse(await readUtf8('package-lock.json'));
const configSource = await readUtf8('tests/E2ETests/playwright.config.ts');
const testSource = await readUtf8('tests/E2ETests/base-accessibility.spec.ts');
const readme = await readUtf8('tests/E2ETests/README.md');
const documentation = await readUtf8('docs/engineering/frontend/e2e-accessibility-visual.md');
const workflow = await readUtf8('.github/workflows/ci.yml');
const qualityGate = await readUtf8('scripts/check-quality.ps1');

assert.equal(packageJson.devDependencies?.['@playwright/test'], '1.62.0');
assert.equal(packageJson.devDependencies?.['@axe-core/playwright'], '4.11.3');
assert.equal(packageJson.devDependencies?.['playwright-core'], '1.62.0');
assert.equal(packageJson.devDependencies?.typescript, '7.0.2');
assert.equal(
  packageJson.scripts?.['typecheck:e2e'],
  'tsc -p tests/E2ETests/tsconfig.json --noEmit --pretty false',
);
assert.equal(
  packageJson.scripts?.['test:e2e'],
  'playwright test --config tests/E2ETests/playwright.config.ts',
);

const rootLock = packageLock.packages?.[''];
assert.equal(rootLock?.devDependencies?.['@playwright/test'], '1.62.0');
assert.equal(rootLock?.devDependencies?.['@axe-core/playwright'], '4.11.3');
assert.equal(rootLock?.devDependencies?.['playwright-core'], '1.62.0');
assert.equal(packageLock.packages?.['node_modules/@playwright/test']?.version, '1.62.0');
assert.equal(packageLock.packages?.['node_modules/@axe-core/playwright']?.version, '4.11.3');
assert.equal(packageLock.packages?.['node_modules/playwright-core']?.version, '1.62.0');

assert.match(configSource, /viewport:\s*\{\s*width:\s*320,\s*height:\s*800\s*\}/s);
assert.match(configSource, /name:\s*['"]chromium-320['"]/);
assert.match(configSource, /browserName:\s*['"]chromium['"]/);
assert.match(configSource, /workers:\s*1/);
assert.match(configSource, /retries:\s*0/);
assert.match(configSource, /locale:\s*['"]es-CR['"]/);
assert.match(configSource, /timezoneId:\s*['"]America\/Costa_Rica['"]/);
assert.match(configSource, /contextOptions:\s*\{\s*reducedMotion:\s*['"]reduce['"]\s*[,}]?/s);
assert.match(configSource, /artifacts\/e2e\/playwright-report/);
assert.match(configSource, /npm run preview --workspace @musica-aprender\/web/);
assert.match(configSource, /const repoRoot = process\.cwd\(\)/);
assert.match(configSource, /join\(repoRoot, ['"]tests\/E2ETests['"]\)/);
assert.doesNotMatch(configSource, /import\.meta|fileURLToPath/);

assert.match(testSource, /AxeBuilder/);
assert.match(testSource, /const repoRoot = process\.cwd\(\)/);
assert.doesNotMatch(testSource, /import\.meta|fileURLToPath/);
for (const tag of ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']) {
  assert.ok(testSource.includes(`'${tag}'`), `Falta tag axe ${tag}`);
}
assert.match(testSource, /Shift\+Tab/);
assert.match(testSource, /keyboard\.press\(['"]Enter['"]\)/);
assert.match(testSource, /:focus-visible/);
assert.match(testSource, /innerWidth/);
assert.match(testSource, /scrollWidth/);
assert.match(testSource, /UI-MVP-001/);
assert.match(testSource, /UI-MVP-002/);
assert.match(testSource, /UI-EST-07/);
assert.match(testSource, /UI-EST-03/);
assert.match(testSource, /音楽で日本語を学ぶ/);
assert.match(testSource, /page\.screenshot/);
assert.match(testSource, /artifacts\/e2e/);

assert.match(workflow, /Verify Playwright, axe and visual test harness/);
assert.match(workflow, /npm run typecheck:e2e/);
assert.match(workflow, /playwright install --with-deps chromium/);
assert.match(workflow, /npm run test:e2e/);

assert.match(qualityGate, /verify-e2e-harness\.mjs/);
assert.match(qualityGate, /npm\.cmd run typecheck:e2e/);
assert.match(qualityGate, /npm\.cmd run test:e2e/);

for (const source of [readme.toLowerCase(), documentation.toLowerCase()]) {
  assert.ok(source.includes('320'));
  assert.ok(source.includes('axe'));
  assert.ok(source.includes('teclado'));
  assert.ok(source.includes('datos manuales'));
  assert.ok(source.includes('manual'));
}

console.log(
  'OK: BL-MVP-022 arnes E2E verificado: Playwright, axe, 320 px, teclado y capturas deterministas.',
);
