import { LegalPage } from '../../components/site';

export const metadata = { title: 'Terms of use' };

export default function Terms() {
  return <LegalPage title="Terms of use">
    <section><h2>App license</h2><p>Recipe Pals is provided by niugengyun, an individual. The iOS app uses <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Apple’s Standard Licensed Application End User License Agreement</a>.</p></section>
    <section><h2>The first release</h2><p>All features in version 1.0 are free. No subscription or in-app purchase is offered in this version. Any future paid offering will disclose its price and conditions before purchase.</p></section>
    <section><h2>Your recipes</h2><p>Use recipes and source material only where you have permission. Keep source attribution where applicable. Saving a recipe or source link does not grant copyright or redistribution rights.</p></section>
    <section><h2>Cooking safely</h2><p>Check ingredients, allergens, quantities, cooking temperatures and instructions against your needs and the original source. Use appropriate food safety practices.</p></section>
    <section><h2>Contact</h2><p>For support, email <a href="mailto:shopkivoo2026@gmail.com">shopkivoo2026@gmail.com</a>. See our <a href="/privacy">privacy policy</a> for information about personal data.</p></section>
  </LegalPage>;
}
