import { useVisibleAccess } from '../../app/access/AccessContext';
import { AppLink } from '../../app/router/navigation';
import './song-crud-guide.css';

type Props = {
  recordingId: string;
  currentRouteId: string;
};

type CrudCopy = {
  title: string;
  create: string;
  read: string;
  update: string;
  remove: string;
};

const copyByRoute: Record<string, CrudCopy> = {
  'UI-MVP-019': {
    title: 'Expediente',
    create: 'Crear otra canción desde el asistente.',
    read: 'Consultar estado, bloqueos, fuente y componentes.',
    update: 'Editar metadatos del DRAFT con guardado seguro.',
    remove:
      'Retirar la publicación o conservar el borrador fuera del flujo; nunca borrar evidencia.',
  },
  'UI-MVP-020': {
    title: 'Derechos y procedencia',
    create: 'Añadir créditos, procedencia y autorizaciones.',
    read: 'Consultar historial, vigencias y alcance.',
    update: 'Corregir datos o sustituir una autorización conservando trazabilidad.',
    remove: 'Revocar/sustituir derechos; la evidencia histórica se conserva.',
  },
  'UI-MVP-021': {
    title: 'Letra',
    create: 'Crear la primera letra o una nueva revisión.',
    read: 'Consultar la revisión vigente y su estructura.',
    update: 'Editar DRAFT; si ya es histórica, crear una revisión correctiva.',
    remove: 'Dejar de usar una revisión en el paquete; no eliminar revisiones históricas.',
  },
  'UI-MVP-022': {
    title: 'Sincronización',
    create: 'Crear sincronización para la fuente y letra exactas.',
    read: 'Consultar timeline y revisión fuente.',
    update: 'Editar DRAFT o crear una revisión compatible.',
    remove: 'Retirar la revisión del paquete sin borrar el historial.',
  },
  'UI-MVP-023': {
    title: 'Traducción',
    create: 'Crear traducción española para la letra exacta.',
    read: 'Comparar japonés, traducción y revisiones.',
    update: 'Editar DRAFT o guardar una nueva revisión correctiva.',
    remove: 'Excluir la revisión del paquete; no borrar traducciones publicadas.',
  },
  'UI-MVP-024': {
    title: 'Análisis lingüístico',
    create: 'Crear análisis ligado a la letra exacta.',
    read: 'Consultar tokens, vocabulario, kanji y gramática modelados.',
    update: 'Editar DRAFT o crear una revisión nueva.',
    remove: 'Retirar una revisión del paquete conservando evidencia e historial.',
  },
  'UI-MVP-025': {
    title: 'Ejercicios',
    create: 'Crear ejercicios DRAFT desde una línea/token exactos.',
    read: 'Consultar definición, revisiones, solución y procedencia.',
    update: 'Editar un DRAFT existente o corregirlo como nueva revisión.',
    remove: 'Dejar de seleccionar la revisión en el paquete; no borrar intentos ni historia.',
  },
  'UI-MVP-026': {
    title: 'Paquete y revisión',
    create: 'Crear un paquete DRAFT con revisiones exactas.',
    read: 'Consultar checklist, checksum, envío e historial.',
    update: 'Cambiar el paquete solo mientras está DRAFT; después se crea otro.',
    remove: 'Retirar/revertir una publicación desde Correcciones sin borrar versiones.',
  },
};

function currentHref(routeId: string, recordingId: string) {
  const id = encodeURIComponent(recordingId);
  switch (routeId) {
    case 'UI-MVP-019':
      return `/editorial/canciones/${id}`;
    case 'UI-MVP-020':
      return `/editorial/canciones/${id}/derechos`;
    case 'UI-MVP-021':
      return `/editorial/canciones/${id}/letra`;
    case 'UI-MVP-022':
      return `/editorial/canciones/${id}/sincronizacion`;
    case 'UI-MVP-023':
      return `/editorial/canciones/${id}/traduccion`;
    case 'UI-MVP-024':
      return `/editorial/canciones/${id}/analisis`;
    case 'UI-MVP-025':
      return `/editorial/canciones/${id}/ejercicios`;
    default:
      return `/editorial/paquetes/${id}`;
  }
}

export function SongCrudGuide({ recordingId, currentRouteId }: Props) {
  const access = useVisibleAccess();
  const copy = copyByRoute[currentRouteId];
  if (!copy) return null;

  const canCorrect = access.capabilities.includes('EDITORIAL.CORRECT');
  const href = currentHref(currentRouteId, recordingId);

  return (
    <section className="song-crud-guide" aria-labelledby="song-crud-guide-title">
      <div className="song-crud-guide__heading">
        <div>
          <p className="song-crud-guide__eyebrow">Gestión CRUD editorial segura</p>
          <strong id="song-crud-guide-title">{copy.title}</strong>
        </div>
        <p>
          En contenido versionado, <strong>U</strong> crea/corrige revisiones y <strong>D</strong>{' '}
          significa retirar, archivar o reemplazar. Las revisiones publicadas y la evidencia no se
          eliminan físicamente.
        </p>
      </div>

      <ul className="song-crud-guide__grid" aria-label={`Operaciones disponibles en ${copy.title}`}>
        <li>
          <span aria-hidden="true">C</span>
          <div>
            <strong>Crear</strong>
            <small>{copy.create}</small>
          </div>
        </li>
        <li>
          <span aria-hidden="true">R</span>
          <div>
            <strong>Consultar</strong>
            <small>{copy.read}</small>
          </div>
        </li>
        <li>
          <span aria-hidden="true">U</span>
          <div>
            <strong>Editar / corregir</strong>
            <small>{copy.update}</small>
          </div>
        </li>
        <li>
          <span aria-hidden="true">D</span>
          <div>
            <strong>Retirar / archivar</strong>
            <small>{copy.remove}</small>
          </div>
        </li>
      </ul>

      <div className="song-crud-guide__actions">
        <AppLink href={href}>Abrir gestión de {copy.title.toLocaleLowerCase('es-CR')}</AppLink>
        {currentRouteId !== 'UI-MVP-026' ? (
          <AppLink href={`/editorial/paquetes/${encodeURIComponent(recordingId)}`}>
            Paquete y revisión
          </AppLink>
        ) : null}
        {canCorrect ? (
          <AppLink href={`/administracion/correcciones/${encodeURIComponent(recordingId)}`}>
            Retirar o revertir publicación
          </AppLink>
        ) : null}
        {currentRouteId === 'UI-MVP-019' ? (
          <AppLink href="/editorial/canciones/nueva">Crear otra canción</AppLink>
        ) : null}
      </div>
    </section>
  );
}
