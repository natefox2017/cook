export default function Home() {
  return <main id="main">
    <section className="home-hero" aria-labelledby="home-title">
      <div className="hero-copy">
        <h1 id="home-title">A little home<br />for your recipes.</h1>
        <p>Keep the dishes you love close. Collect recipes, plan what’s next,
          and find your rhythm in the kitchen with Recipe Pals.</p>
        <a className="button" href="/download">Get Recipe Pals for iPhone <span aria-hidden="true">→</span></a>
        <p className="hero-note">Made for your own collection.</p>
      </div>
      <figure className="hero-photo">
        <img src="/images/onboarding-shrimp-pasta.jpg" alt="Shrimp pasta with lemon and fresh herbs, from the Recipe Pals app artwork" width="1024" height="1536" fetchPriority="high" />
        <figcaption>Good food, kept close.</figcaption>
      </figure>
    </section>

    <section id="your-kitchen" className="app-story" aria-labelledby="app-title">
      <div className="story-heading"><h2 id="app-title">From “save this”<br />to “let’s cook”.</h2>
        <p>A personal recipe collection that stays useful long after the first save.</p></div>
      <div className="feature-list">
        <article><h3>Gather your favorites</h3><p>Bring recipes into Recipe Pals from links and the iPhone share sheet. Keep the original source with the dishes you save.</p></article>
        <article><h3>Make the week easier</h3><p>Organize your collection, plan meals and turn ingredients into a private grocery checklist.</p></article>
        <article><h3>Stay with the cooking</h3><p>Follow ingredients and instructions in a focused cooking view, one step at a time.</p></article>
      </div>
    </section>

    <section className="sharing-story" aria-labelledby="sharing-title">
      <h2 id="sharing-title">Someone sent you a recipe?</h2>
      <div><p>Open their Recipe Pals link to read the shared ingredients and steps in your browser. You don’t need an account or the app to read an available recipe.</p>
        <p className="secondary">Shared recipes are accessed through their individual links. A publisher can withdraw a recipe at any time.</p></div>
    </section>

    <section className="home-close"><h2>Make room for<br />your next favorite.</h2>
      <a className="button" href="/download">Get the app <span aria-hidden="true">→</span></a></section>
  </main>;
}
