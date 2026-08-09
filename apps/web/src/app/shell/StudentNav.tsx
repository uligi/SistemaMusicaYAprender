import { AppLink } from '../router/navigation';

export type StudentNavProps = {
  pathname: string;
};

const items = [
  { label: 'Explorar', href: '/canciones', prefix: '/canciones' },
  { label: 'Aprender', href: '/aprender/ejemplo', prefix: '/aprender' },
  { label: 'Progreso', href: '/progreso', prefix: '/progreso' },
  { label: 'Preferencias', href: '/preferencias', prefix: '/preferencias' },
] as const;

export function StudentNav({ pathname }: StudentNavProps) {
  return (
    <nav aria-label="Navegación del estudiante" className="student-nav">
      <div className="student-nav__inner">
        {items.map((item) => (
          <AppLink
            className="student-nav__link"
            current={pathname.startsWith(item.prefix)}
            href={item.href}
            key={item.label}
          >
            {item.label}
          </AppLink>
        ))}
      </div>
    </nav>
  );
}
