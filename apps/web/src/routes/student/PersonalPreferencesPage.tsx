import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Button, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';

const httpClient = createHttpClient();

type AntiforgeryTokenResponse = {
  requestToken: string;
  headerName: string;
};

type JapanesePreferences = {
  showKanji: boolean;
  showKana: boolean;
  furiganaMode: string;
  romajiMode: string;
  showNaturalTranslation: boolean;
};

type AccessibilityPreferences = {
  fontScalePercent: number;
  highContrast: boolean;
  reducedMotion: boolean;
  flashProtection: boolean;
};

type PrivacyPreferences = {
  activityVisibility: string;
};

type PreferenceValues = {
  interfaceLanguage: string;
  translationLanguage: string;
  japanese: JapanesePreferences;
  accessibility: AccessibilityPreferences;
  privacy: PrivacyPreferences;
  provenance: {
    contractVersion: number;
    languageCatalogVersion: number;
  };
};

type PreferenceResponse = {
  preferenceSetId: string;
  version: number;
  revisionNo: number;
  values: PreferenceValues;
  updatedAt: string;
  profile: {
    displayName: string | null;
    uiLanguage: string;
    timeZone: string;
    version: number;
  };
  options: {
    languages: readonly {
      code: string;
      label: string;
      version: number;
    }[];
    furiganaModes: readonly string[];
    romajiModes: readonly string[];
    fontScalePercents: readonly number[];
    privacyVisibilities: readonly string[];
  };
};

type PreferenceDraft = Omit<PreferenceValues, 'provenance'> & {
  version: number;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready' }
  | { phase: 'saving' }
  | { phase: 'confirmed'; message: string }
  | { phase: 'failed'; problem: ClientProblem };

const furiganaLabels: Record<string, string> = {
  ALWAYS: 'Mostrar siempre',
  AUTO: 'Adaptativo',
  HIDDEN: 'Ocultar',
};

const romajiLabels: Record<string, string> = {
  ALWAYS: 'Mostrar siempre',
  HELP: 'Solo como ayuda',
  HIDDEN: 'Ocultar',
};

function applyAccessibility(values: PreferenceValues) {
  const root = document.documentElement;
  root.dataset.userMotion = values.accessibility.reducedMotion ? 'reduced' : 'full';
  root.dataset.userContrast = values.accessibility.highContrast ? 'high' : 'standard';
  root.dataset.userFlash = values.accessibility.flashProtection ? 'protected' : 'standard';
  root.style.setProperty('--user-font-scale', `${values.accessibility.fontScalePercent / 100}`);
}

function toDraft(response: PreferenceResponse): PreferenceDraft {
  return {
    version: response.version,
    interfaceLanguage: response.values.interfaceLanguage,
    translationLanguage: response.values.translationLanguage,
    japanese: { ...response.values.japanese },
    accessibility: { ...response.values.accessibility },
    privacy: { ...response.values.privacy },
  };
}

export function PersonalPreferencesPage() {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const activeRequest = useRef<AbortController | null>(null);
  const [response, setResponse] = useState<PreferenceResponse>();
  const [draft, setDraft] = useState<PreferenceDraft>();
  const [state, setState] = useState<PageState>({ phase: 'loading' });

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();
    activeRequest.current = controller;

    const load = async () => {
      const result = await httpClient.get<PreferenceResponse>('/preferences', {
        cacheMode: 'no-store',
        retry: 'never',
        signal: controller.signal,
      });

      if (activeRequest.current !== controller || result.kind === 'cancelled') return;
      activeRequest.current = null;

      if (!result.ok) {
        setState({ phase: 'failed', problem: result.problem });
        return;
      }

      setResponse(result.data);
      setDraft(toDraft(result.data));
      applyAccessibility(result.data.values);
      setState({ phase: 'ready' });
    };

    void load();

    return () => controller.abort();
  }, []);

  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!draft) return;

    if (!draft.japanese.showKanji && !draft.japanese.showKana) {
      setState({
        phase: 'failed',
        problem: {
          kind: 'validation',
          status: null,
          code: 'identity.preferences.japanese-layer.required',
          summary: 'Conserva al menos una capa japonesa',
          cause: 'Kanji y kana no pueden quedar ocultos al mismo tiempo.',
          correction: 'Activa kanji o kana antes de confirmar.',
          dataPreserved: true,
          retryable: false,
          fieldErrors: [],
        },
      });
      return;
    }

    activeRequest.current?.abort();
    const controller = new AbortController();
    activeRequest.current = controller;
    setState({ phase: 'saving' });

    const antiforgery = await httpClient.get<AntiforgeryTokenResponse>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
      signal: controller.signal,
    });

    if (antiforgery.kind === 'cancelled') return;
    if (!antiforgery.ok) {
      setState({ phase: 'failed', problem: antiforgery.problem });
      return;
    }

    const result = await httpClient.put<PreferenceDraft, PreferenceResponse>(
      '/preferences',
      draft,
      {
        headers: {
          [antiforgery.data.headerName]: antiforgery.data.requestToken,
        },
        retry: 'never',
        signal: controller.signal,
        invalidate: ['/preferences'],
      },
    );

    if (activeRequest.current !== controller || result.kind === 'cancelled') return;
    activeRequest.current = null;

    if (!result.ok) {
      setState({ phase: 'failed', problem: result.problem });
      return;
    }

    setResponse(result.data);
    setDraft(toDraft(result.data));
    applyAccessibility(result.data.values);
    setState({
      phase: 'confirmed',
      message: `Revisión ${result.data.revisionNo} confirmada. Tus elecciones se aplicarán también al volver a iniciar sesión.`,
    });
  };

  if (!response || !draft) {
    return (
      <article className="route-surface preferences" data-route-id="UI-MVP-008">
        <p className="eyebrow">UI-MVP-008 · Área estudiante</p>
        <h1 id="route-title" ref={headingRef} tabIndex={-1}>
          Preferencias
        </h1>
        {state.phase === 'failed' ? (
          <StateMessage
            description={state.problem.correction}
            state="UI-EST-06"
            title={state.problem.summary}
          />
        ) : (
          <StateMessage
            description="Recuperando solo el perfil de producto y la última revisión confirmada."
            state="UI-EST-11"
            title="Cargando preferencias"
          />
        )}
      </article>
    );
  }

  return (
    <article className="route-surface preferences" data-route-id="UI-MVP-008">
      <div className="preferences__intro">
        <p className="eyebrow">UI-MVP-008 · Área estudiante</p>
        <h1 id="route-title" ref={headingRef} tabIndex={-1}>
          Preferencias
        </h1>
        <p>
          Configura idioma, ayudas de lectura, accesibilidad y privacidad. Las credenciales de
          acceso permanecen fuera de este perfil.
        </p>
        <dl className="preferences__profile" aria-label="Perfil básico">
          <div>
            <dt>Idioma regional</dt>
            <dd>{response.profile.uiLanguage}</dd>
          </div>
          <div>
            <dt>Zona horaria</dt>
            <dd>{response.profile.timeZone}</dd>
          </div>
          <div>
            <dt>Revisión confirmada</dt>
            <dd>{response.revisionNo}</dd>
          </div>
        </dl>
      </div>

      <form aria-busy={state.phase === 'saving'} className="preferences__form" onSubmit={save}>
        <fieldset>
          <legend>Idioma</legend>
          <label htmlFor="preference-interface-language">Idioma de interfaz</label>
          <select
            id="preference-interface-language"
            onChange={(event) => {
              const value = event.currentTarget.value;
              setDraft((current) => (current ? { ...current, interfaceLanguage: value } : current));
            }}
            value={draft.interfaceLanguage}
          >
            {response.options.languages.map((language) => (
              <option key={language.code} value={language.code}>
                {language.label}
              </option>
            ))}
          </select>

          <label htmlFor="preference-translation-language">Idioma principal de traducción</label>
          <select
            id="preference-translation-language"
            onChange={(event) => {
              const value = event.currentTarget.value;
              setDraft((current) =>
                current ? { ...current, translationLanguage: value } : current,
              );
            }}
            value={draft.translationLanguage}
          >
            {response.options.languages.map((language) => (
              <option key={language.code} value={language.code}>
                {language.label}
              </option>
            ))}
          </select>
          <p className="preferences__help">
            Español es el valor P0 publicado. El japonés original no cambia al elegir una
            traducción.
          </p>
        </fieldset>

        <fieldset>
          <legend>Presentación del japonés</legend>
          <label className="preferences__check">
            <input
              checked={draft.japanese.showKanji}
              onChange={(event) => {
                const checked = event.currentTarget.checked;
                setDraft((current) =>
                  current
                    ? {
                        ...current,
                        japanese: { ...current.japanese, showKanji: checked },
                      }
                    : current,
                );
              }}
              type="checkbox"
            />
            Mostrar kanji
          </label>
          <label className="preferences__check">
            <input
              checked={draft.japanese.showKana}
              onChange={(event) => {
                const checked = event.currentTarget.checked;
                setDraft((current) =>
                  current
                    ? {
                        ...current,
                        japanese: { ...current.japanese, showKana: checked },
                      }
                    : current,
                );
              }}
              type="checkbox"
            />
            Mostrar kana
          </label>

          <label htmlFor="preference-furigana">Furigana</label>
          <select
            id="preference-furigana"
            onChange={(event) => {
              const value = event.currentTarget.value;
              setDraft((current) =>
                current
                  ? {
                      ...current,
                      japanese: { ...current.japanese, furiganaMode: value },
                    }
                  : current,
              );
            }}
            value={draft.japanese.furiganaMode}
          >
            {response.options.furiganaModes.map((mode) => (
              <option key={mode} value={mode}>
                {furiganaLabels[mode] ?? mode}
              </option>
            ))}
          </select>

          <label htmlFor="preference-romaji">Romaji</label>
          <select
            id="preference-romaji"
            onChange={(event) => {
              const value = event.currentTarget.value;
              setDraft((current) =>
                current
                  ? {
                      ...current,
                      japanese: { ...current.japanese, romajiMode: value },
                    }
                  : current,
              );
            }}
            value={draft.japanese.romajiMode}
          >
            {response.options.romajiModes.map((mode) => (
              <option key={mode} value={mode}>
                {romajiLabels[mode] ?? mode}
              </option>
            ))}
          </select>

          <label className="preferences__check">
            <input
              checked={draft.japanese.showNaturalTranslation}
              onChange={(event) => {
                const checked = event.currentTarget.checked;
                setDraft((current) =>
                  current
                    ? {
                        ...current,
                        japanese: {
                          ...current.japanese,
                          showNaturalTranslation: checked,
                        },
                      }
                    : current,
                );
              }}
              type="checkbox"
            />
            Mostrar traducción natural
          </label>
        </fieldset>

        <fieldset>
          <legend>Accesibilidad</legend>
          <label htmlFor="preference-font-scale">Escala de lectura</label>
          <select
            id="preference-font-scale"
            onChange={(event) => {
              const value = Number(event.currentTarget.value);
              setDraft((current) =>
                current
                  ? {
                      ...current,
                      accessibility: {
                        ...current.accessibility,
                        fontScalePercent: value,
                      },
                    }
                  : current,
              );
            }}
            value={draft.accessibility.fontScalePercent}
          >
            {response.options.fontScalePercents.map((value) => (
              <option key={value} value={value}>
                {value} %
              </option>
            ))}
          </select>

          <label className="preferences__check">
            <input
              checked={draft.accessibility.highContrast}
              onChange={(event) => {
                const checked = event.currentTarget.checked;
                setDraft((current) =>
                  current
                    ? {
                        ...current,
                        accessibility: {
                          ...current.accessibility,
                          highContrast: checked,
                        },
                      }
                    : current,
                );
              }}
              type="checkbox"
            />
            Contraste reforzado
          </label>
          <label className="preferences__check">
            <input
              checked={draft.accessibility.reducedMotion}
              onChange={(event) => {
                const checked = event.currentTarget.checked;
                setDraft((current) =>
                  current
                    ? {
                        ...current,
                        accessibility: {
                          ...current.accessibility,
                          reducedMotion: checked,
                        },
                      }
                    : current,
                );
              }}
              type="checkbox"
            />
            Reducir movimiento
          </label>
          <label className="preferences__check">
            <input
              checked={draft.accessibility.flashProtection}
              onChange={(event) => {
                const checked = event.currentTarget.checked;
                setDraft((current) =>
                  current
                    ? {
                        ...current,
                        accessibility: {
                          ...current.accessibility,
                          flashProtection: checked,
                        },
                      }
                    : current,
                );
              }}
              type="checkbox"
            />
            Protección contra destellos
          </label>
        </fieldset>

        <fieldset>
          <legend>Privacidad</legend>
          <label htmlFor="preference-privacy">Actividad educativa</label>
          <select
            id="preference-privacy"
            onChange={(event) => {
              const value = event.currentTarget.value;
              setDraft((current) =>
                current
                  ? {
                      ...current,
                      privacy: { activityVisibility: value },
                    }
                  : current,
              );
            }}
            value={draft.privacy.activityVisibility}
          >
            <option value="PRIVATE">Privada</option>
          </select>
          <p className="preferences__help">
            El MVP no publica progreso, respuestas, notas ni historial por defecto.
          </p>
        </fieldset>

        <Button disabled={state.phase === 'saving'} type="submit">
          {state.phase === 'saving' ? 'Guardando…' : 'Confirmar preferencias'}
        </Button>
      </form>

      {state.phase === 'saving' ? (
        <StateMessage
          description="Se creará una nueva revisión solo si la configuración cambió."
          state="UI-EST-11"
          title="Guardando preferencias"
        />
      ) : null}

      {state.phase === 'confirmed' ? (
        <StateMessage
          description={state.message}
          state="UI-EST-12"
          title="Preferencias confirmadas"
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          description={state.problem.correction}
          state={state.problem.kind === 'conflict' ? 'UI-EST-10' : 'UI-EST-06'}
          title={state.problem.summary}
        />
      ) : null}
    </article>
  );
}
