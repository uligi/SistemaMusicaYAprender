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
          Completa los mínimos canónicos en orden. El asistente reutiliza los servicios editoriales
          existentes y termina en un borrador; guardar no publica contenido.
        </p>
      </header>

      <ol className="new-song-assistant__steps" aria-label="Pasos para registrar una nueva canción">
        <li>
          <strong>1. Artista canónico</strong>
          <span>
            Busca una identidad existente o registra una nueva después de revisar duplicados.
          </span>
        </li>
        <li>
          <strong>2. Obra, grabación y fuente</strong>
          <span>Registra la obra, la versión concreta y la referencia exacta de YouTube.</span>
        </li>
        <li>
          <strong>3. Borrador guardado</strong>
          <span>
            Abre el expediente y continúa derechos y procedencia sin editar la base directamente.
          </span>
        </li>
      </ol>

      <aside className="new-song-assistant__boundary" aria-label="Límite del asistente">
        <strong>Resultado de este flujo:</strong>
        <span>
          un borrador editorial con identidades estables. La revisión y publicación pertenecen a
          etapas posteriores.
        </span>
      </aside>

      <ArtistAdministrationPage />
    </article>
  );
}
