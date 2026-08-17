import './study-session-journey.css';

export type StudyJourneyStage = 'start' | 'exercise' | 'result';
export type StudyJourneyStatus = 'pending' | 'saved' | 'confirmed';

type StudySessionJourneyProps = {
  stage: StudyJourneyStage;
  status: StudyJourneyStatus;
  description?: string;
};

const steps: ReadonlyArray<{ key: StudyJourneyStage; label: string }> = [
  { key: 'start', label: 'Inicio' },
  { key: 'exercise', label: 'Ejercicio' },
  { key: 'result', label: 'Resultado' },
];

const statusCopy: Record<StudyJourneyStatus, { label: string; description: string }> = {
  pending: {
    label: 'Pendiente',
    description:
      'Todavía no hay una respuesta confirmada. Si sales antes de confirmar, recuperas la misma instancia congelada, pero la selección local no se guarda.',
  },
  saved: {
    label: 'Guardado',
    description:
      'La respuesta ya está confirmada y se conserva al salir o recargar. La corrección o la evidencia pueden seguir pendientes.',
  },
  confirmed: {
    label: 'Confirmado',
    description:
      'La evaluación y su evidencia ya están confirmadas. Salir, volver o recargar reutiliza los mismos registros; este paso todavía no actualiza progreso.',
  },
};

export function StudySessionJourney({ stage, status, description }: StudySessionJourneyProps) {
  const copy = statusCopy[status];

  return (
    <section className="study-session-journey" aria-labelledby="study-session-journey-title">
      <div className="study-session-journey__heading">
        <p className="eyebrow">RECORRIDO DE SESIÓN</p>
        <h2 id="study-session-journey-title">Inicio, ejercicio y resultado</h2>
      </div>

      <ol className="study-session-journey__steps" aria-label="Etapas de la sesión de estudio">
        {steps.map((step, index) => (
          <li key={step.key} aria-current={step.key === stage ? 'step' : undefined}>
            <span aria-hidden="true">{index + 1}</span>
            <strong>{step.label}</strong>
          </li>
        ))}
      </ol>

      <p className="study-session-journey__status" data-study-status={status} aria-live="polite">
        <strong>Estado: {copy.label}.</strong> {description ?? copy.description}
      </p>
    </section>
  );
}
