import { LegalPage } from '../../components/site';

export const metadata = { title: 'Terms of use', robots: { index: false, follow: false } };

export default function Terms() {
  return <LegalPage title="Terms of use">
    <section><h2>Using Recipe Pals</h2><p>Recipe Pals helps you collect, organize and cook recipes for personal use. Final terms must identify the service operator, eligibility, applicable law and the effective date before release.</p></section>
    <section><h2>Your content and its sources</h2><p>Only import and share content you have permission to use. Keep original attribution where applicable. Saving a link or importing a recipe does not give you copyright or distribution rights in someone else’s work.</p></section>
    <section><h2>Sharing a recipe</h2><p>Publish only content you are entitled to distribute. An individual shared page is available to people with its link until it is withdrawn or otherwise unavailable. Do not place sensitive personal information in content you publish.</p></section>
    <section><h2>Cooking and food safety</h2><p>Check ingredients, allergens, quantities, temperatures and instructions against the original source and your own needs. Imported or AI-assisted content can be incomplete or incorrect. Use appropriate food safety practices.</p></section>
    <section><h2>Purchases and subscriptions</h2><p>Where purchases are offered, review the actual App Store product details, price, renewal terms and cancellation instructions shown at purchase. This website does not establish a price, free trial or subscription entitlement.</p></section>
    <section><h2>Availability and changes</h2><p>Features and shared content may become unavailable. Final rules for account termination, service changes, liability, dispute resolution and support must be reviewed for the release region and stated in the completed terms.</p></section>
  </LegalPage>;
}
