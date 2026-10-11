import './globals.css';
import { Header, Footer } from '../components/site';
import { siteURL } from '../lib/site.mjs';

export const metadata = {
  metadataBase: siteURL() || undefined,
  title: { default: 'Recipe Pals — Your personal recipe collection', template: '%s · Recipe Pals' },
  description: 'Collect your recipes, organize your kitchen and cook step by step with Recipe Pals for iPhone.',
};

export default function RootLayout({ children }) {
  return <html lang="en"><body>
    <a className="skip-link" href="#main">Skip to content</a>
    <Header />{children}<Footer />
  </body></html>;
}
