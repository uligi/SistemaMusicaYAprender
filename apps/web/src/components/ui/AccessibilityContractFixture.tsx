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
} from './index';

type FixtureRow = {
  id: string;
  title: string;
};

const columns: readonly DataColumn<FixtureRow>[] = [
  { key: 'title', header: 'Canción', render: (row) => row.title },
];

const rows: readonly FixtureRow[] = [{ id: 'fixture-1', title: 'Kaijū' }];

const states: readonly UiStateId[] = [
  'UI-EST-01',
  'UI-EST-02',
  'UI-EST-03',
  'UI-EST-04',
  'UI-EST-05',
  'UI-EST-06',
  'UI-EST-07',
  'UI-EST-08',
  'UI-EST-09',
  'UI-EST-10',
  'UI-EST-11',
  'UI-EST-12',
];

export function AccessibilityContractFixture() {
  return (
    <section data-component-catalog="bl-mvp-019" aria-label="Fixture de regresión accesible">
      <Button>Acción</Button>
      <Link href="/">Enlace</Link>
      <Field id="fixture-field" label="Campo" />
      <SelectField id="fixture-select" label="Select">
        <option value="es">Español</option>
      </SelectField>
      <Dialog triggerLabel="Abrir" title="Diálogo" description="Fixture" confirmLabel="Confirmar">
        <Alert title="Atención" tone="warning">
          Fixture accesible.
        </Alert>
      </Dialog>
      <Tabs
        label="Fixture"
        items={[
          {
            id: 'ja',
            label: 'Japonés',
            content: <span lang="ja">音楽で日本語を学ぶ</span>,
          },
        ]}
      />
      <DataTable caption="Fixture" columns={columns} getRowKey={(row) => row.id} rows={rows} />
      {states.map((state) => (
        <StateMessage description="Fixture" key={state} state={state} title={state} />
      ))}
    </section>
  );
}
