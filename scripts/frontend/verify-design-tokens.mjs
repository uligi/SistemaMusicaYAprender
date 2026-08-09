import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const sourceRoot = path.join(repoRoot, 'apps', 'web', 'src');
const tokenPath = path.join(sourceRoot, 'styles', 'tokens', 'v1.css');
const indexPath = path.join(sourceRoot, 'styles', 'index.css');
const htmlPath = path.join(repoRoot, 'apps', 'web', 'index.html');
const docsPath = path.join(repoRoot, 'docs', 'engineering', 'frontend', 'design-tokens.md');

function fail(message) {
  console.error(`ERROR BL-MVP-018: ${message}`);
  process.exitCode = 1;
}

function collectFiles(directory, predicate) {
  const found = [];

  if (!fs.existsSync(directory)) {
    return found;
  }

  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolutePath = path.join(directory, entry.name);

    if (entry.isDirectory()) {
      found.push(...collectFiles(absolutePath, predicate));
    } else if (predicate(absolutePath)) {
      found.push(absolutePath);
    }
  }

  return found.sort();
}

for (const requiredPath of [tokenPath, indexPath, htmlPath, docsPath]) {
  if (!fs.existsSync(requiredPath)) {
    fail(`falta ${path.relative(repoRoot, requiredPath)}`);
  }
}

if (process.exitCode) {
  process.exit(process.exitCode);
}

const tokens = fs.readFileSync(tokenPath, 'utf8');
const indexCss = fs.readFileSync(indexPath, 'utf8');
const html = fs.readFileSync(htmlPath, 'utf8');
const docs = fs.readFileSync(docsPath, 'utf8');

const requiredTokens = new Map([
  ['--ma-design-token-version', '1'],
  ['--ma-color-ink', '#182338'],
  ['--ma-color-muted', '#5b6475'],
  ['--ma-color-primary', '#2f4eb2'],
  ['--ma-color-success', '#107c66'],
  ['--ma-color-warning', '#9a5b00'],
  ['--ma-color-danger', '#b83a3a'],
  ['--ma-color-surface', '#f7f8fc'],
  ['--ma-color-border', '#d9deea'],
  ['--ma-font-size-secondary', '0.875rem'],
  ['--ma-font-size-body', '1rem'],
  ['--ma-font-size-japanese', '1.125rem'],
  ['--ma-font-size-page-title-min', '1.75rem'],
  ['--ma-font-size-page-title-max', '2.25rem'],
  ['--ma-space-1', '0.25rem'],
  ['--ma-space-2', '0.5rem'],
  ['--ma-space-3', '0.75rem'],
  ['--ma-space-4', '1rem'],
  ['--ma-space-5', '1.5rem'],
  ['--ma-space-6', '2rem'],
  ['--ma-space-7', '3rem'],
  ['--ma-space-8', '4rem'],
  ['--ma-radius-control', '0.625rem'],
  ['--ma-radius-panel', '0.875rem'],
  ['--ma-radius-surface', '1.125rem'],
  ['--ma-touch-target', '2.75rem'],
]);

for (const [name, value] of requiredTokens) {
  const pattern = new RegExp(
    `${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:\\s*${value.replace(
      /[.*+?^${}()|[\]\\]/g,
      '\\$&',
    )}\\s*;`,
    'i',
  );

  if (!pattern.test(tokens)) {
    fail(`token requerido ${name}: ${value} no coincide`);
  }
}

if (!tokens.includes("'Noto Sans'") || !tokens.includes("'Noto Sans JP'")) {
  fail('las pilas tipograficas deben incluir Noto Sans y Noto Sans JP');
}

if (!tokens.includes('@media (prefers-reduced-motion: reduce)')) {
  fail('falta prefers-reduced-motion: reduce');
}

const reducedBlock = tokens.match(/@media \(prefers-reduced-motion: reduce\)\s*\{([\s\S]+)\}\s*$/);

if (!reducedBlock || !/--ma-motion-duration-standard:\s*0ms/.test(reducedBlock[1])) {
  fail('movimiento reducido no lleva la duracion estandar a 0ms');
}

if (!indexCss.startsWith("@import './tokens/v1.css';")) {
  fail('index.css debe importar tokens/v1.css como primera regla');
}

const consumerStylePaths = collectFiles(
  sourceRoot,
  (absolutePath) => absolutePath.endsWith('.css') && absolutePath !== tokenPath,
);
const consumerStyles = consumerStylePaths
  .map((absolutePath) => fs.readFileSync(absolutePath, 'utf8'))
  .join('\n');

if (/(#[0-9a-f]{3,8}\b|rgba?\(|hsla?\()/i.test(consumerStyles)) {
  fail('el CSS consumidor contiene un color crudo; los colores deben venir de tokens');
}

const consumedFamilies = [
  '--ma-color-',
  '--ma-font-',
  '--ma-space-',
  '--ma-radius-',
  '--ma-elevation-',
  '--ma-motion-',
];

for (const family of consumedFamilies) {
  if (!consumerStyles.includes(`var(${family}`)) {
    fail(`el CSS consumidor no usa la familia ${family}`);
  }
}

const textSourcePaths = collectFiles(
  sourceRoot,
  (absolutePath) =>
    absolutePath.endsWith('.tsx') || absolutePath.endsWith('.ts') || absolutePath.endsWith('.css'),
);
const sourceText = textSourcePaths
  .map((sourcePath) => fs.readFileSync(sourcePath, 'utf8'))
  .join('\n');

if (!sourceText.includes('data-design-tokens="v1"')) {
  fail('el arbol de UI no declara la version visual v1');
}

if (!sourceText.includes('lang="ja"')) {
  fail('el arbol de UI no ejercita el contrato tipografico japones con lang="ja"');
}

const expectedJapanese = '\u97F3\u697D\u3067\u65E5\u672C\u8A9E\u3092\u5B66\u3076';
const suspiciousMojibake = /[\u00C2\u00C3\uFFFD]/;

if (!sourceText.includes(expectedJapanese)) {
  fail('el arbol de UI no conserva el literal japones UTF-8 de referencia');
}

for (const sourcePath of textSourcePaths) {
  const content = fs.readFileSync(sourcePath, 'utf8');

  if (suspiciousMojibake.test(content)) {
    fail(`${path.relative(repoRoot, sourcePath)} contiene marcadores tipicos de mojibake`);
  }
}

if (!/<meta\s+charset=["']UTF-8["']\s*\/?>/i.test(html)) {
  fail('index.html debe declarar meta charset UTF-8');
}

if (!indexCss.includes('color-scheme: only light;')) {
  fail('index.css debe fijar color-scheme: only light para la linea base visual clara');
}

if (!docs.includes('Tokens visuales v1') || !docs.includes('prefers-reduced-motion')) {
  fail('la documentacion de tokens v1 esta incompleta');
}

if (!process.exitCode) {
  console.log(
    'OK: BL-MVP-018 tokens v1 verificados: definicion, consumo transversal, UTF-8 y movimiento reducido.',
  );
}
