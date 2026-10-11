import { storeURL } from '../../lib/site.mjs';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'Download' };

export default function Download() {
  const url = storeURL();
  return <main id="main" className="download-page">
    <img className="download-icon" src="/images/app-icon.png" width="112" height="112" alt="Recipe Pals app icon" />
    <h1>Your kitchen,<br />a little more organized.</h1>
    <p>Recipe Pals is a personal recipe collection and cooking app for iPhone.</p>
    {url ? <a className="button" href={url} rel="noopener noreferrer">Download on the App Store <span aria-hidden="true">↗</span></a>
      : <div className="notice"><strong>Download link coming soon</strong><p>The verified App Store download link isn’t available here yet. Please check back for release information.</p></div>}
    <p className="secondary">Requires iOS 18 or later. No Android download is currently listed.</p>
    <div className="download-links"><a href="/privacy">Privacy policy</a><a href="/terms">Terms of use</a></div>
  </main>;
}
