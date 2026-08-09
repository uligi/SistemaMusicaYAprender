import type { ReactNode } from 'react';

export type UiStateId =
  | 'UI-EST-01'
  | 'UI-EST-02'
  | 'UI-EST-03'
  | 'UI-EST-04'
  | 'UI-EST-05'
  | 'UI-EST-06'
  | 'UI-EST-07'
  | 'UI-EST-08'
  | 'UI-EST-09'
  | 'UI-EST-10'
  | 'UI-EST-11'
  | 'UI-EST-12';

type StateTone = 'info' | 'success' | 'warning' | 'danger';

export type StateMessageProps = {
  state: UiStateId;
  title: string;
  description: string;
  action?: ReactNode;
};

const stateTone: Record<UiStateId, StateTone> = {
  'UI-EST-01': 'info',
  'UI-EST-02': 'info',
  'UI-EST-03': 'info',
  'UI-EST-04': 'info',
  'UI-EST-05': 'warning',
  'UI-EST-06': 'warning',
  'UI-EST-07': 'warning',
  'UI-EST-08': 'danger',
  'UI-EST-09': 'danger',
  'UI-EST-10': 'warning',
  'UI-EST-11': 'info',
  'UI-EST-12': 'success',
};

export function StateMessage({ action, description, state, title }: StateMessageProps) {
  const tone = stateTone[state];

  return (
    <section
      aria-busy={state === 'UI-EST-01' || state === 'UI-EST-02' || state === 'UI-EST-11'}
      aria-live="polite"
      className="ma-state"
      data-state={state}
      data-tone={tone}
      role="status"
    >
      <p className="ma-state__id">{state}</p>
      <h3>{title}</h3>
      <p>{description}</p>
      {action ? <div className="ma-state__action">{action}</div> : null}
    </section>
  );
}
