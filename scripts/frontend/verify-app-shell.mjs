import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();

const requiredFiles = [
  'apps/web/src/app/App.tsx',
  'apps/web/src/app/access/AccessContext.tsx',
  'apps/web/src/app/access/AccessBoundary.tsx',
  'apps/web/src/app/router/AppRouter.tsx',
  'apps/web/src/app/router/route-manifest.ts',
  'apps/web/src/app/router/match-route.ts',
  'apps/web/src/app/router/navigation.tsx',
  'apps/web/src/app/shell/AppShell.tsx',
  'apps/web/src/app/shell/PublicHeader.tsx',
  'apps/web/src/app/shell/StudentNav.tsx',
  'apps/web/src/app/shell/BackofficeShell.tsx',
  'apps/web/src/app/shell/BackofficeSidebar.tsx',
  'apps/web/src/app/shell/shell.css',
  'apps/web/src/routes/public/PublicArea.tsx',
  'apps/web/src/routes/student/StudentArea.tsx',
  'apps/web/src/routes/editorial/EditorialArea.tsx',
  'apps/web/src/routes/administration/AdministrationArea.tsx',
  'docs/engineering/frontend/app-shell-routing.md',
  'infrastructure/containers/web/nginx.conf',
];

const fail = (message) => {
  console.error(`ERROR BL-MVP-020: ${message}`);
  process.exit(1);
};

for (const relativePath of requiredFiles) {
  if (!fs.existsSync(path.join(repoRoot, relativePath))) {
    fail(`falta ${relativePath}`);
  }
}

const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
const manifest = read('apps/web/src/app/router/route-manifest.ts');
const router = read('apps/web/src/app/router/AppRouter.tsx');
const accessContext = read('apps/web/src/app/access/AccessContext.tsx');
const boundary = read('apps/web/src/app/access/AccessBoundary.tsx');
const appShell = read('apps/web/src/app/shell/AppShell.tsx');
const studentNav = read('apps/web/src/app/shell/StudentNav.tsx');
const backoffice = read('apps/web/src/app/shell/BackofficeShell.tsx');
const backofficeSidebar = read('apps/web/src/app/shell/BackofficeSidebar.tsx');
const navigation = read('apps/web/src/app/router/navigation.tsx');
const matcher = read('apps/web/src/app/router/match-route.ts');
const shellCss = read('apps/web/src/app/shell/shell.css');
const indexCss = read('apps/web/src/styles/index.css');
const nginx = read('infrastructure/containers/web/nginx.conf');
const docs = read('docs/engineering/frontend/app-shell-routing.md');

const expectedRoutes = [
  ['UI-MVP-001', '/'],
  ['UI-MVP-002', '/canciones'],
  ['UI-MVP-003', '/canciones?consulta='],
  ['UI-MVP-004', '/canciones/{slug}'],
  ['UI-MVP-005', '/registro'],
  ['UI-MVP-006', '/verificar-cuenta'],
  ['UI-MVP-007', '/acceso'],
  ['UI-MVP-008', '/preferencias'],
  ['UI-MVP-009', '/aprender/{slug}'],
  ['UI-MVP-010', '/aprender/{slug}/analisis/{token}'],
  ['UI-MVP-011', '/estudiar/{slug}'],
  ['UI-MVP-012', '/estudiar/{slug}/ejercicio/{id}'],
  ['UI-MVP-013', '/estudiar/{slug}/resultado/{id}'],
  ['UI-MVP-014', '/progreso'],
  ['UI-MVP-015', '/progreso/canciones/{slug}'],
  ['UI-MVP-016', '/reanudar'],
  ['UI-MVP-017', '/editorial'],
  ['UI-MVP-018', '/editorial/canciones/nueva'],
  ['UI-MVP-019', '/editorial/canciones/{id}'],
  ['UI-MVP-020', '/editorial/canciones/{id}/derechos'],
  ['UI-MVP-021', '/editorial/canciones/{id}/letra'],
  ['UI-MVP-022', '/editorial/canciones/{id}/sincronizacion'],
  ['UI-MVP-023', '/editorial/canciones/{id}/traduccion'],
  ['UI-MVP-024', '/editorial/canciones/{id}/analisis'],
  ['UI-MVP-025', '/editorial/canciones/{id}/ejercicios'],
  ['UI-MVP-026', '/editorial/paquetes/{id}'],
  ['UI-MVP-027', '/administracion/publicaciones/{id}'],
  ['UI-MVP-028', '/administracion/correcciones/{id}'],
  ['UI-MVP-029', '/administracion/roles'],
  ['UI-MVP-030', '/administracion/configuracion'],
  ['UI-MVP-031', '/administracion/auditoria'],
  ['UI-MVP-032', '/administracion/auditoria/{evento}'],
];

for (const [id, routePath] of expectedRoutes) {
  if (!manifest.includes(`id: '${id}'`)) {
    fail(`falta ${id} en el manifiesto`);
  }

  const routeLiteral =
    id === 'UI-MVP-003' ? `canonicalPath: '${routePath}'` : `path: '${routePath}'`;

  if (!manifest.includes(routeLiteral)) {
    fail(`${id} no conserva la ruta ${routePath}`);
  }
}

const idMatches = manifest.match(/id:\s*'UI-MVP-\d{3}'/g) ?? [];
if (idMatches.length !== 32) {
  fail(`el manifiesto debe contener 32 pantallas; encontro ${idMatches.length}`);
}

for (const area of ['public', 'student', 'editorial', 'administration']) {
  if (!manifest.includes(`area: '${area}'`)) {
    fail(`falta el area ${area}`);
  }
}

for (const lazyImport of [
  "lazy(() => import('../../routes/public/PublicArea'))",
  "lazy(() => import('../../routes/student/StudentArea'))",
  "lazy(() => import('../../routes/editorial/EditorialArea'))",
  "lazy(() => import('../../routes/administration/AdministrationArea'))",
]) {
  if (!router.includes(lazyImport)) {
    fail(`falta carga por ruta: ${lazyImport}`);
  }
}

for (const contract of [
  'AccessBoundary',
  'evaluateVisibleAccess',
  '<Suspense',
  'Ruta no disponible',
  'UI-EST-01',
]) {
  if (!router.includes(contract)) {
    fail(`AppRouter no contiene ${contract}`);
  }
}

for (const contract of [
  "source: 'anonymous-bootstrap'",
  'isAuthenticated: false',
  'capabilities',
]) {
  if (!accessContext.includes(contract)) {
    fail(`AccessContext no contiene ${contract}`);
  }
}

if (/localStorage|sessionStorage/.test(accessContext + boundary + navigation)) {
  fail('la sesión visible no puede persistirse en Web Storage');
}

for (const contract of [
  "route.access === 'student'",
  'requiredCapabilities',
  'access.capabilities.includes',
  'El servidor vuelve a autorizar',
]) {
  if (!boundary.includes(contract)) {
    fail(`AccessBoundary no contiene ${contract}`);
  }
}

if (
  /roleName|currentRole|isAdmin|isEditor/.test(boundary + backoffice + backofficeSidebar + manifest)
) {
  fail('la frontera visible debe decidir por capacidades, no por nombres de rol');
}

for (const label of ['Explorar', 'Aprender', 'Progreso', 'Preferencias']) {
  if (!studentNav.includes(`'${label}'`)) {
    fail(`StudentNav no contiene ${label}`);
  }
}

if (
  !backoffice.includes('<BackofficeSidebar access={access} pathname={pathname} />') ||
  !backofficeSidebar.includes('access.capabilities.includes')
) {
  fail('BackofficeShell no calcula navegación desde capacidades');
}

for (const contract of [
  'Saltar al contenido',
  'id="main-content"',
  'data-app-shell="bl-mvp-020"',
  'data-design-tokens="v1"',
]) {
  if (!appShell.includes(contract)) {
    fail(`AppShell no contiene ${contract}`);
  }
}

if (!navigation.includes('window.history.pushState') || !navigation.includes('popstate')) {
  fail('la navegación interna no usa History API con evento de ubicación');
}

if (!matcher.includes('URLSearchParams') || !matcher.includes('route.queryKey')) {
  fail('el matcher no distingue la ruta de búsqueda por query string');
}

if (!nginx.includes('try_files $uri $uri/ /index.html;')) {
  fail('Nginx no conserva fallback para carga directa de rutas cliente');
}

for (const contract of [
  '@media (max-width: 29.9375rem)',
  'var(--ma-touch-target)',
  '@media (prefers-reduced-motion: reduce)',
]) {
  if (!shellCss.includes(contract)) {
    fail(`shell.css no contiene ${contract}`);
  }
}

if (!(shellCss + indexCss).includes('var(--ma-focus-ring)')) {
  fail('los estilos del shell no conservan el token de foco visible');
}

for (const contract of ['UI-MVP-001-032', 'servidor', 'React.lazy', 'capacidades', '320 px']) {
  if (!docs.includes(contract)) {
    fail(`documentación BL-MVP-020 no contiene ${contract}`);
  }
}

console.log(
  'OK: BL-MVP-020 app shell verificado: 32 rutas, cuatro areas lazy, fronteras visibles por sesion/capacidad y autoridad del servidor.',
);
