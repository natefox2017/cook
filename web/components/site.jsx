export function Header() {
  return <header className="site-header">
    <a className="wordmark" href="/" aria-label="Recipe Pals home">
      <img src="/images/app-icon.png" width="40" height="40" alt="" />
      <span>Recipe Pals</span>
    </a>
    <nav aria-label="Main navigation">
      <a href="/#your-kitchen">The app</a>
      <a className="button small" href="/download">Get the app</a>
    </nav>
  </header>;
}

export function Footer() {
  return <footer className="site-footer">
    <a className="footer-brand" href="/">Recipe Pals</a>
    <p>Your recipes. Your kitchen.</p>
    <nav aria-label="Footer navigation">
      <a href="/download">Download</a>
      <a href="/privacy">Privacy policy</a>
      <a href="/terms">Terms of use</a>
    </nav>
  </footer>;
}

export function LegalPage({ title, children }) {
  return <main id="main" className="reading-page">
    <a className="back-link" href="/">Back to home</a>
    <h1>{title}</h1>
    <div className="notice"><strong>Pre-release draft</strong>
      <p>This document is a draft for review. The operator’s details, contact address,
        effective date and final legal terms must be completed before release.</p>
    </div>
    {children}
    <a className="back-link" href="/download">Download information</a>
  </main>;
}
