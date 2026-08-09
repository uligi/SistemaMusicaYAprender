import type { ReactNode } from 'react';

export type DataColumn<T> = {
  key: string;
  header: string;
  render: (row: T) => ReactNode;
};

export type DataTableProps<T> = {
  caption: string;
  columns: readonly DataColumn<T>[];
  rows: readonly T[];
  getRowKey: (row: T) => string;
  emptyMessage?: string;
};

export function DataTable<T>({
  caption,
  columns,
  emptyMessage = 'No hay datos para mostrar.',
  getRowKey,
  rows,
}: DataTableProps<T>) {
  if (rows.length === 0) {
    return (
      <div className="ma-table-empty" role="status">
        <strong>{caption}</strong>
        <p>{emptyMessage}</p>
      </div>
    );
  }

  return (
    <div className="ma-table-wrap">
      <table className="ma-data-table">
        <caption>{caption}</caption>
        <thead>
          <tr>
            {columns.map((column) => (
              <th key={column.key} scope="col">
                {column.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={getRowKey(row)}>
              {columns.map((column) => (
                <td key={column.key} data-label={column.header}>
                  {column.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
