import { useEffect, useRef } from 'react';
import { ArtistAdministrationPage } from './ArtistAdministrationPage';
import './new-song-assistant.css';

export function NewSongAssistantPage() {
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    headingRef.current?.focus();
  }, []);

  return (
    <article className="route-surface new-song-assistant" data-route-id="UI-MVP-018">
      <header className="new-song-assistant__header">
        <p className="eyebrow">BL-MVP-045 · UI-MVP-018</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Nueva canción
        </h1>
        <p>
          Registra una canción en tres pasos sencillos. Primero elige el artista, después completa
          los datos de la canción y su video de YouTube, y al final continúa trabajando desde el
          expediente.
        </p>
      </header>

      <section className="new-song-assistant__prep" aria-labelledby="new-song-prep-title">
        <div>
          <p className="eyebrow">Antes de empezar</p>
          <h2 id="new-song-prep-title">Ten a mano estos tres datos</h2>
        </div>
        <ul>
          <li>
            <strong>Artista</strong>
            <span>Nombre original, romanización o alias para encontrarlo.</span>
          </li>
          <li>
            <strong>Título</strong>
            <span>El título original de la canción, preferiblemente en japonés.</span>
          </li>
          <li>
            <strong>YouTube</strong>
            <span>La URL del video que corresponde exactamente a esa grabación.</span>
          </li>
        </ul>
      </section>

      <ol className="new-song-assistant__steps" aria-label="Pasos para registrar una nueva canción">
        <li>
          <span className="new-song-assistant__step-number" aria-hidden="true">
            1
          </span>
          <div>
            <strong>1. Artista canónico</strong>
            <span>Busca primero un artista existente; crea uno nuevo solo si hace falta.</span>
          </div>
        </li>
        <li>
          <span className="new-song-assistant__step-number" aria-hidden="true">
            2
          </span>
          <div>
            <strong>2. Obra, grabación y fuente</strong>
            <span>Completa el título, la versión y la referencia exacta de YouTube.</span>
          </div>
        </li>
        <li>
          <span className="new-song-assistant__step-number" aria-hidden="true">
            3
          </span>
          <div>
            <strong>3. Borrador guardado</strong>
            <span>Abre el expediente para continuar con letra, derechos y demás tareas.</span>
          </div>
        </li>
      </ol>

      <aside className="new-song-assistant__boundary" aria-label="Qué ocurre al guardar">
        <strong>Guardar aquí no publica la canción.</strong>
        <span>
          El resultado es un borrador editorial. Podrás completar letra, traducción, análisis,
          sincronización y derechos antes de cualquier publicación.
        </span>
      </aside>

      <ArtistAdministrationPage />
    </article>
  );
}
