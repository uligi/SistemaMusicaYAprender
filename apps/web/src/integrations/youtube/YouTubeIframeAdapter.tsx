import { useEffect, useId, useRef, useState } from 'react';
import { StateMessage } from '../../components/ui';
import './youtube-iframe-adapter.css';

const iframeApiUrl = 'https://www.youtube.com/iframe_api';
const privacyHost = 'https://www.youtube-nocookie.com';
const loadTimeoutMs = 1_500;

export type YouTubePlayerState =
  'unstarted' | 'ended' | 'playing' | 'paused' | 'buffering' | 'cued';

export type YouTubeAdapterEvent =
  | { type: 'ready' }
  | { type: 'state'; state: YouTubePlayerState }
  | { type: 'error'; code: number };

export type YouTubePlayerController = {
  play: () => void;
  pause: () => void;
  seek: (seconds: number) => void;
  getCurrentTime: () => number;
};

type YouTubePlayerLike = {
  destroy: () => void;
  playVideo: () => void;
  pauseVideo: () => void;
  seekTo: (seconds: number, allowSeekAhead: boolean) => void;
  getCurrentTime: () => number;
};

type YouTubePlayerEvent = {
  target: YouTubePlayerLike;
};

type YouTubeStateEvent = {
  data: number;
};

type YouTubeErrorEvent = {
  data: number;
};

type YouTubePlayerOptions = {
  events: {
    onReady: (event: YouTubePlayerEvent) => void;
    onStateChange: (event: YouTubeStateEvent) => void;
    onError: (event: YouTubeErrorEvent) => void;
  };
};

type YouTubeNamespace = {
  Player: new (element: HTMLElement | string, options: YouTubePlayerOptions) => YouTubePlayerLike;
  PlayerState?: Readonly<Record<string, number>>;
};

type YouTubeWindow = Window & {
  YT?: YouTubeNamespace;
  onYouTubeIframeAPIReady?: () => void;
};

let apiPromise: Promise<YouTubeNamespace> | null = null;

function isValidExternalRef(value: string) {
  return /^[A-Za-z0-9_-]{11}$/.test(value);
}

function buildEmbedUrl(externalRef: string) {
  const params = new URLSearchParams({
    enablejsapi: '1',
    origin: window.location.origin,
    playsinline: '1',
    rel: '0',
  });

  return `${privacyHost}/embed/${externalRef}?${params.toString()}`;
}

function playerState(value: number): YouTubePlayerState {
  switch (value) {
    case 0:
      return 'ended';
    case 1:
      return 'playing';
    case 2:
      return 'paused';
    case 3:
      return 'buffering';
    case 5:
      return 'cued';
    default:
      return 'unstarted';
  }
}

function loadIframeApi(): Promise<YouTubeNamespace> {
  const youtubeWindow = window as YouTubeWindow;

  if (youtubeWindow.YT?.Player) {
    return Promise.resolve(youtubeWindow.YT);
  }

  if (apiPromise) {
    return apiPromise;
  }

  apiPromise = new Promise<YouTubeNamespace>((resolve, reject) => {
    let settled = false;
    const previousReady = youtubeWindow.onYouTubeIframeAPIReady;

    const finish = (callback: () => void) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeout);
      callback();
    };

    youtubeWindow.onYouTubeIframeAPIReady = () => {
      previousReady?.();
      const namespace = youtubeWindow.YT;
      if (!namespace?.Player) {
        finish(() => reject(new Error('youtube-iframe-api-missing')));
        return;
      }

      finish(() => resolve(namespace));
    };

    const timeout = window.setTimeout(() => {
      finish(() => reject(new Error('youtube-iframe-api-timeout')));
    }, loadTimeoutMs);

    const existing = document.querySelector<HTMLScriptElement>(
      'script[data-youtube-iframe-api="true"]',
    );

    if (existing) {
      existing.addEventListener(
        'error',
        () => finish(() => reject(new Error('youtube-iframe-api-blocked'))),
        { once: true },
      );
      return;
    }

    const script = document.createElement('script');
    script.src = iframeApiUrl;
    script.async = true;
    script.dataset.youtubeIframeApi = 'true';
    script.referrerPolicy = 'strict-origin-when-cross-origin';
    script.addEventListener(
      'error',
      () => finish(() => reject(new Error('youtube-iframe-api-blocked'))),
      { once: true },
    );
    document.head.append(script);
  }).catch((error: unknown) => {
    apiPromise = null;
    throw error;
  });

  return apiPromise;
}

type AdapterPhase = 'idle' | 'loading' | 'ready' | 'blocked' | 'failed';

export type YouTubeIframeAdapterProps = {
  externalRef: string;
  title: string;
  headingLevel?: 2 | 3 | 4;
  onEvent?: (event: YouTubeAdapterEvent) => void;
  onControllerReady?: (controller: YouTubePlayerController | null) => void;
};

export function YouTubeIframeAdapter({
  externalRef,
  title,
  headingLevel = 2,
  onEvent,
  onControllerReady,
}: YouTubeIframeAdapterProps) {
  const rawId = useId();
  const containerId = `youtube-player-${rawId.replace(/[^A-Za-z0-9_-]/g, '')}`;
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const playerRef = useRef<YouTubePlayerLike | null>(null);
  const [activated, setActivated] = useState(false);
  const [phase, setPhase] = useState<AdapterPhase>('idle');
  const [state, setState] = useState<YouTubePlayerState>('unstarted');
  const Heading = headingLevel === 4 ? 'h4' : headingLevel === 3 ? 'h3' : 'h2';

  useEffect(() => {
    if (!activated || !isValidExternalRef(externalRef) || !iframeRef.current) {
      return;
    }

    let cancelled = false;
    setPhase('loading');

    void loadIframeApi()
      .then((youtube) => {
        if (cancelled || !iframeRef.current) return;

        const player = new youtube.Player(iframeRef.current, {
          events: {
            onReady: (event) => {
              if (cancelled) return;
              playerRef.current = event.target;
              setPhase('ready');
              onControllerReady?.({
                play: () => event.target.playVideo(),
                pause: () => event.target.pauseVideo(),
                seek: (seconds) => event.target.seekTo(Math.max(0, seconds), true),
                getCurrentTime: () => Math.max(0, event.target.getCurrentTime()),
              });
              onEvent?.({ type: 'ready' });
            },
            onStateChange: (event) => {
              if (cancelled) return;
              const nextState = playerState(event.data);
              setState(nextState);
              onEvent?.({ type: 'state', state: nextState });
            },
            onError: (event) => {
              if (cancelled) return;
              onControllerReady?.(null);
              onEvent?.({ type: 'error', code: event.data });
              setPhase(event.data === 101 || event.data === 150 ? 'blocked' : 'failed');
            },
          },
        });

        playerRef.current = player;
      })
      .catch(() => {
        if (!cancelled) {
          onControllerReady?.(null);
          setPhase('blocked');
        }
      });

    return () => {
      cancelled = true;
      onControllerReady?.(null);
      playerRef.current?.destroy();
      playerRef.current = null;
    };
  }, [activated, externalRef, onControllerReady, onEvent]);

  if (!isValidExternalRef(externalRef)) {
    return (
      <StateMessage
        state="UI-EST-06"
        title="Fuente audiovisual no válida"
        description="La referencia de YouTube no tiene el formato permitido y no se intentará cargar una dependencia externa."
      />
    );
  }

  return (
    <section
      className="youtube-iframe-adapter"
      aria-labelledby={`${containerId}-heading`}
      data-youtube-adapter
    >
      <header className="youtube-iframe-adapter__header">
        <p className="eyebrow">BL-MVP-058 · ADAPTADOR YOUTUBE IFRAME</p>
        <Heading id={`${containerId}-heading`}>Fuente audiovisual</Heading>
        <p>
          El contenido propio ya está disponible. YouTube solo se carga cuando decides iniciar el
          reproductor.
        </p>
      </header>

      {!activated ? (
        <div className="youtube-iframe-adapter__consent">
          <button
            type="button"
            onClick={() => {
              setActivated(true);
              setPhase('loading');
            }}
          >
            Cargar reproductor de YouTube
          </button>
          <p>Se usará el modo de privacidad mejorada y la referencia exacta de esta grabación.</p>
        </div>
      ) : null}

      {activated && phase !== 'blocked' && phase !== 'failed' ? (
        <div className="youtube-iframe-adapter__frame-shell">
          <iframe
            id={containerId}
            ref={iframeRef}
            className="youtube-iframe-adapter__frame"
            src={buildEmbedUrl(externalRef)}
            title={`Reproductor de YouTube para ${title}`}
            data-video-id={externalRef}
            loading="eager"
            referrerPolicy="strict-origin-when-cross-origin"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowFullScreen
          />
        </div>
      ) : null}

      {phase === 'loading' ? (
        <p className="youtube-iframe-adapter__status">Cargando reproductor externo…</p>
      ) : null}

      {phase === 'ready' ? (
        <p className="youtube-iframe-adapter__status">Reproductor listo · estado: {state}.</p>
      ) : null}

      {phase === 'blocked' ? (
        <StateMessage
          state="UI-EST-06"
          title="YouTube no está disponible"
          description="El reproductor fue bloqueado, no puede incrustarse o la red externa falló. El contenido educativo propio permanece disponible."
        />
      ) : null}

      {phase === 'failed' ? (
        <StateMessage
          state="UI-EST-06"
          title="No se pudo reproducir la fuente externa"
          description="YouTube informó un error del reproductor. Puedes seguir usando el contenido educativo propio."
        />
      ) : null}
    </section>
  );
}
