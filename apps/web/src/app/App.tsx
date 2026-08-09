export function App() {
  return (
    <main className="app-shell" data-design-tokens="v1">
      <section className="welcome-card" aria-labelledby="welcome-title">
        <p className="eyebrow">Sistema visual v1 · BL-MVP-018</p>
        <h1 id="welcome-title">Música y Aprender</h1>
        <p className="welcome-card__japanese" lang="ja">
          音楽で日本語を学ぶ
        </p>
        <p>
          La base visual ya consume tokens versionados para color, tipografía, espaciado, radios,
          elevación y movimiento antes de construir los componentes accesibles.
        </p>
      </section>
    </main>
  );
}
