import { LegalPage } from '../../components/site';

export const metadata = { title: 'Help & Support' };

export default function Support() {
  return <LegalPage title="Help & Support">
    <p>Recipe Pals is your private recipe collection and cooking companion. Version 1.0 is completely free.</p>
    <section><h2>Contact support</h2><p>Email <a href="mailto:shopkivoo2026@gmail.com">shopkivoo2026@gmail.com</a>. Include your app version, iOS version, what happened and the steps that led to it. Screenshots are helpful if you remove private information. Never send passwords or sign-in codes.</p></section>
    <section><h2>Start your collection</h2><p>Choose Get Started or Skip in the introduction, then tap + in Recipes to create a recipe. Add ingredients and steps, organize favorites and collections, and open Cooking Mode when you are ready to cook. Local features work without an account.</p></section>
    <section><h2>Export and delete data</h2><p>Use the app’s data settings to export your library before deleting anything. Delete Local Data affects this iPhone; it does not delete your cloud account. Use the account-deletion control to delete your account and associated cloud data. Contact support if you cannot access these controls.</p></section>
    <section><h2>About the operator</h2><p>Recipe Pals is operated by niugengyun, an individual. Read the <a href="/privacy">privacy policy</a> and <a href="/terms">terms of use</a>.</p></section>
  </LegalPage>;
}
