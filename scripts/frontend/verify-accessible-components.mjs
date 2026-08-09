import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const repoRoot = process.cwd();

const requiredFiles = [
  'apps/web/src/components/ui/Button.tsx',
  'apps/web/src/components/ui/Link.tsx',
  'apps/web/src/components/ui/Field.tsx',
  'apps/web/src/components/ui/SelectField.tsx',
  'apps/web/src/components/ui/Dialog.tsx',
  'apps/web/src/components/ui/DataTable.tsx',
  'apps/web/src/components/ui/Tabs.tsx',
  'apps/web/src/components/ui/Alert.tsx',
  'apps/web/src/components/ui/StateMessage.tsx',
  'apps/web/src/components/ui/AccessibilityContractFixture.tsx',
  'apps/web/src/components/ui/ui.css',
  'apps/web/src/components/ui/index.ts',
  'apps/web/src/styles/index.css',
  'docs/engineering/frontend/accessible-components.md',
];

const fail = (message) => {
  console.error(`ERROR BL-MVP-019: ${message}`);
  process.exit(1);
};

for (const relativePath of requiredFiles) {
  if (!fs.existsSync(path.join(repoRoot, relativePath))) {
    fail(`falta ${relativePath}`);
  }
}

const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');

const button = read('apps/web/src/components/ui/Button.tsx');
const link = read('apps/web/src/components/ui/Link.tsx');
const field = read('apps/web/src/components/ui/Field.tsx');
const select = read('apps/web/src/components/ui/SelectField.tsx');
const dialog = read('apps/web/src/components/ui/Dialog.tsx');
const table = read('apps/web/src/components/ui/DataTable.tsx');
const tabs = read('apps/web/src/components/ui/Tabs.tsx');
const alert = read('apps/web/src/components/ui/Alert.tsx');
const state = read('apps/web/src/components/ui/StateMessage.tsx');
const fixture = read('apps/web/src/components/ui/AccessibilityContractFixture.tsx');
const uiCss = read('apps/web/src/components/ui/ui.css');
const indexCss = read('apps/web/src/styles/index.css');
const docs = read('docs/engineering/frontend/accessible-components.md');

const expectAll = (content, values, label) => {
  for (const value of values) {
    if (!content.includes(value)) {
      fail(`${label} no contiene: ${value}`);
    }
  }
};

expectAll(button, ['forwardRef', '<button', "type = 'button'"], 'Button');
expectAll(link, ['<a', 'href={href}'], 'Link');
expectAll(
  field,
  ['<label', 'htmlFor={id}', 'aria-describedby', 'aria-invalid', 'role="alert"'],
  'Field',
);
expectAll(
  select,
  ['<label', 'htmlFor={id}', '<select', 'aria-describedby', 'aria-invalid', 'role="alert"'],
  'SelectField',
);
expectAll(
  dialog,
  [
    '<dialog',
    'showModal()',
    'aria-labelledby',
    'aria-describedby',
    'onClose={restoreTriggerFocus}',
    'triggerRef.current?.focus()',
  ],
  'Dialog',
);
expectAll(table, ['<table', '<caption', 'scope="col"', 'data-label={column.header}'], 'DataTable');
expectAll(
  tabs,
  [
    'role="tablist"',
    'role="tab"',
    'role="tabpanel"',
    'aria-selected',
    'aria-controls',
    "case 'ArrowRight'",
    "case 'ArrowLeft'",
    "case 'Home'",
    "case 'End'",
    'event.preventDefault()',
    'tabRefs.current[index]?.focus()',
  ],
  'Tabs',
);
expectAll(alert, ['aria-live', "role={assertive ? 'alert' : 'status'}", 'toneLabels'], 'Alert');

for (let index = 1; index <= 12; index += 1) {
  const id = `UI-EST-${String(index).padStart(2, '0')}`;

  if (!state.includes(`'${id}'`) || !fixture.includes(`'${id}'`)) {
    fail(`falta cobertura del estado ${id}`);
  }
}

expectAll(
  uiCss,
  [
    'min-height: var(--ma-touch-target)',
    ':focus-visible',
    'var(--ma-focus-ring)',
    '.ma-dialog::backdrop',
    '@media (max-width: 29.9375rem)',
    '.ma-data-table td::before',
    'content: attr(data-label)',
  ],
  'ui.css',
);

if (/outline\s*:\s*(?:0|none)\b/i.test(uiCss)) {
  fail('ui.css no puede suprimir el foco visible');
}

if (!indexCss.startsWith("@import './tokens/v1.css';\n@import '../components/ui/ui.css';")) {
  fail('index.css debe importar tokens v1 antes del CSS de componentes');
}

expectAll(
  fixture,
  [
    'data-component-catalog="bl-mvp-019"',
    '<Button',
    '<Link',
    '<Field',
    '<SelectField',
    '<Dialog',
    '<DataTable',
    '<Tabs',
    '<Alert',
    '<StateMessage',
    'lang="ja"',
  ],
  'AccessibilityContractFixture.tsx',
);

expectAll(
  docs,
  [
    'Componentes accesibles esenciales',
    'DI-MVP-01',
    'DI-MVP-14',
    'UI-EST-01',
    'UI-EST-12',
    'retorno del foco',
    '320 px',
    'AccessibilityContractFixture.tsx',
  ],
  'documentación',
);

console.log(
  'OK: BL-MVP-019 componentes accesibles verificados: semantica, teclado, foco, dialogo, tabla, pestanas, alertas y estados.',
);
