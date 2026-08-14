import { CreditProvenancePage } from './CreditProvenancePage';
import { RightsAdministrationPanel } from './RightsAdministrationPanel';
import './rights-provenance.css';

export type RightsProvenancePageProps = {
  recordingId: string;
};

function scrollToSection(id: string) {
  const target = document.getElementById(id);
  if (!target) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  target.scrollIntoView({
    behavior: reducedMotion ? 'auto' : 'smooth',
    block: 'start',
  });
}

export function RightsProvenancePage({ recordingId }: RightsProvenancePageProps) {
  return (
    <div className="rights-provenance" data-route-id="UI-MVP-020">
      <nav
        className="rights-provenance__navigator"
        aria-label="Guía rápida de derechos y procedencia"
      >
        <div className="rights-provenance__navigator-copy">
          <p className="eyebrow">Flujo guiado</p>
          <strong>Completa la procedencia antes de tomar decisiones de derechos.</strong>
        </div>
        <div className="rights-provenance__navigator-actions">
          <button type="button" onClick={() => scrollToSection('credit-provenance-title')}>
            <span aria-hidden="true">1</span>
            <span>
              <strong>Créditos y fuentes</strong>
              <small>Quién participa y de dónde sale la información</small>
            </span>
          </button>
          <button type="button" onClick={() => scrollToSection('rights-admin-title')}>
            <span aria-hidden="true">2</span>
            <span>
              <strong>Derechos y disponibilidad</strong>
              <small>Qué uso está autorizado, dónde y hasta cuándo</small>
            </span>
          </button>
        </div>
      </nav>

      <CreditProvenancePage recordingId={recordingId} />
      <RightsAdministrationPanel recordingId={recordingId} />
    </div>
  );
}
