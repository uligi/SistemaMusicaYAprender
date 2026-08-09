import type { ReactNode } from 'react';

export type AlertTone = 'info' | 'success' | 'warning' | 'danger';

export type AlertProps = {
  tone?: AlertTone;
  title: string;
  children: ReactNode;
};

const toneLabels: Record<AlertTone, string> = {
  info: 'Información',
  success: 'Confirmado',
  warning: 'Atención',
  danger: 'Error',
};

export function Alert({ children, title, tone = 'info' }: AlertProps) {
  const assertive = tone === 'danger';

  return (
    <div
      aria-live={assertive ? 'assertive' : 'polite'}
      className="ma-alert"
      data-tone={tone}
      role={assertive ? 'alert' : 'status'}
    >
      <strong>
        <span className="ma-alert__tone">{toneLabels[tone]}:</span> {title}
      </strong>
      <div>{children}</div>
    </div>
  );
}
