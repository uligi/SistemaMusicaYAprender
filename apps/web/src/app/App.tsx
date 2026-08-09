import {
  Alert,
  Button,
  DataTable,
  Dialog,
  Field,
  Link,
  SelectField,
  StateMessage,
  Tabs,
  type DataColumn,
  type UiStateId,
} from '../components/ui';

type SongRow = {
  id: string;
  title: string;
  artist: string;
  status: string;
};

const songRows: readonly SongRow[] = [
  { id: 'song-1', title: 'Kaijū', artist: 'Sakanaction', status: 'Disponible' },
  { id: 'song-2', title: 'Ejemplo de estudio', artist: 'Catálogo interno', status: 'En revisión' },
];

const songColumns: readonly DataColumn<SongRow>[] = [
  { key: 'title', header: 'Canción', render: (row) => row.title },
  { key: 'artist', header: 'Artista', render: (row) => row.artist },
  { key: 'status', header: 'Estado', render: (row) => row.status },
];

const stateExamples: readonly {
  id: UiStateId;
  title: string;
  description: string;
}[] = [
  {
    id: 'UI-EST-01',
    title: 'Carga inicial',
    description: 'Reserva el espacio y anuncia el estado una sola vez.',
  },
  {
    id: 'UI-EST-02',
    title: 'Carga progresiva',
    description: 'El contenido propio permanece disponible mientras otra parte termina de cargar.',
  },
  {
    id: 'UI-EST-03',
    title: 'Sin resultados',
    description: 'Explica la consulta y permite limpiar filtros sin inventar resultados externos.',
  },
  {
    id: 'UI-EST-04',
    title: 'Vacío autorizado',
    description: 'Explica por qué no hay elementos y ofrece solo acciones concedidas.',
  },
  {
    id: 'UI-EST-05',
    title: 'YouTube no disponible',
    description: 'La letra y el contenido educativo propio siguen siendo utilizables.',
  },
  {
    id: 'UI-EST-06',
    title: 'Red interrumpida',
    description: 'Conserva lo elegible y ofrece un reintento explícito.',
  },
  {
    id: 'UI-EST-07',
    title: 'Sesión vencida',
    description: 'Solicita autenticación sin afirmar que una escritura no confirmada fue guardada.',
  },
  {
    id: 'UI-EST-08',
    title: 'Acceso denegado',
    description: 'No revela datos ni permisos ajenos y ofrece una ruta segura.',
  },
  {
    id: 'UI-EST-09',
    title: 'Validación',
    description: 'Indica campo, causa y corrección mientras conserva los datos válidos.',
  },
  {
    id: 'UI-EST-10',
    title: 'Conflicto de versión',
    description: 'Ofrece recargar o copiar cambios sin sobrescribir a ciegas.',
  },
  {
    id: 'UI-EST-11',
    title: 'Guardando',
    description: 'Evita doble confirmación y mantiene el foco disponible.',
  },
  {
    id: 'UI-EST-12',
    title: 'Confirmado',
    description: 'Presenta el resultado confirmado y la siguiente acción disponible.',
  },
];

export function App() {
  return (
    <main className="component-catalog" data-component-catalog="bl-mvp-019" data-design-tokens="v1">
      <header className="catalog-hero" aria-labelledby="catalog-title">
        <p className="eyebrow">EP-02 · BL-MVP-019</p>
        <h1 id="catalog-title">Componentes accesibles esenciales</h1>
        <p>
          Catálogo base para teclado, foco, semántica y tecnologías de asistencia antes de construir
          las rutas funcionales.
        </p>
        <p className="catalog-hero__japanese" lang="ja">
          音楽で日本語を学ぶ
        </p>
      </header>

      <section className="catalog-section" aria-labelledby="actions-title">
        <h2 id="actions-title">Acciones y navegación</h2>
        <div className="catalog-row">
          <Button>Acción principal</Button>
          <Button variant="secondary">Acción secundaria</Button>
          <Button variant="danger">Acción de riesgo</Button>
          <Link href="#states">Ir a estados</Link>
        </div>
      </section>

      <section className="catalog-section" aria-labelledby="form-title">
        <h2 id="form-title">Campos de formulario</h2>
        <form className="catalog-form" onSubmit={(event) => event.preventDefault()}>
          <Field
            id="display-name"
            label="Nombre visible"
            helpText="Se muestra dentro de la plataforma."
            autoComplete="nickname"
          />
          <Field
            id="email-example"
            label="Correo de ejemplo"
            type="email"
            error="Escribe una dirección con formato nombre@dominio."
            defaultValue="correo-incompleto"
          />
          <SelectField
            id="language"
            label="Idioma de interfaz"
            helpText="El contenido japonés conserva su idioma semántico."
            defaultValue="es-CR"
          >
            <option value="es-CR">Español (Costa Rica)</option>
            <option value="en">English</option>
            <option value="it">Italiano</option>
          </SelectField>
          <Button type="submit">Validar ejemplo</Button>
        </form>
      </section>

      <section className="catalog-section" aria-labelledby="dialog-title">
        <h2 id="dialog-title">Diálogo modal</h2>
        <p>Escape cierra el diálogo nativo y al cerrar el foco vuelve al disparador.</p>
        <Dialog
          triggerLabel="Revisar confirmación"
          title="Confirmar acción"
          description="Revisa el alcance antes de continuar. Este ejemplo no modifica datos."
          confirmLabel="Confirmar ejemplo"
        >
          <Alert tone="warning" title="Revisión requerida">
            La confirmación se presenta con texto además de color.
          </Alert>
        </Dialog>
      </section>

      <section className="catalog-section" aria-labelledby="tabs-title">
        <h2 id="tabs-title">Pestañas</h2>
        <Tabs
          label="Capas educativas"
          items={[
            {
              id: 'japanese',
              label: 'Japonés',
              content: (
                <p lang="ja">
                  日本語の本文は言語を明示し、キーボード操作から独立して読み上げられます。
                </p>
              ),
            },
            {
              id: 'translation',
              label: 'Español',
              content: (
                <p>La traducción visible es una capa separada del contenido canónico japonés.</p>
              ),
            },
            {
              id: 'analysis',
              label: 'Análisis',
              content: (
                <p>
                  Las flechas, Inicio y Fin cambian de pestaña y mueven el foco de forma explícita.
                </p>
              ),
            },
          ]}
        />
      </section>

      <section className="catalog-section" aria-labelledby="alerts-title">
        <h2 id="alerts-title">Alertas y mensajes</h2>
        <div className="catalog-stack">
          <Alert tone="info" title="Información">
            El estado incluye una etiqueta textual.
          </Alert>
          <Alert tone="success" title="Guardado">
            La operación de ejemplo quedó confirmada.
          </Alert>
          <Alert tone="warning" title="Revisión">
            Comprueba los datos antes de continuar.
          </Alert>
          <Alert tone="danger" title="No se pudo completar">
            Corrige el dato indicado y vuelve a intentarlo.
          </Alert>
        </div>
      </section>

      <section className="catalog-section" aria-labelledby="table-title">
        <h2 id="table-title">Tabla semántica</h2>
        <DataTable
          caption="Canciones de ejemplo"
          columns={songColumns}
          rows={songRows}
          getRowKey={(row) => row.id}
        />
      </section>

      <section className="catalog-section" id="states" aria-labelledby="states-title">
        <h2 id="states-title">Estados obligatorios UI-EST-01 a UI-EST-12</h2>
        <div className="state-grid">
          {stateExamples.map((state) => (
            <StateMessage
              key={state.id}
              state={state.id}
              title={state.title}
              description={state.description}
            />
          ))}
        </div>
      </section>
    </main>
  );
}
