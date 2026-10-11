import { LegalPage } from '../../components/site';

export const metadata = { title: 'Privacy policy', robots: { index: false, follow: false } };

export default function Privacy() {
  return <LegalPage title="Privacy policy">
    <section><h2>Your personal collection</h2><p>Recipe Pals is designed around a private recipe collection. Your recipe content, source links, shopping lists and meal plans are used to provide the features you choose. Collecting a recipe does not automatically publish it to this website.</p></section>
    <section><h2>Accounts and cloud features</h2><p>Account, authentication and cloud synchronization features require processing account information and the content you choose to synchronize. Final release disclosures must identify the operator, processors, hosting regions, retention periods and deletion procedure.</p></section>
    <section><h2>Import and AI processing</h2><p>Import features may send submitted links, text or files to backend services. Features using AI, OCR or audio processing may require third-party processing. The released policy must name the enabled providers and explain the content sent to them before those features are offered.</p></section>
    <section><h2>Recipes shared through links</h2><p>When you explicitly publish a recipe, a filtered snapshot can be read by anyone who has its link. Sharing does not grant access to your private collection. Treat a shared link as accessible to its recipients and anyone they forward it to. Withdrawal stops future access through the service, but cannot erase copies someone already saved.</p></section>
    <section><h2>This website</h2><p>This implementation does not add advertising trackers, analytics cookies or visitor accounts. Hosting and upstream services may process request information to serve and protect the website. The operator must document the actual hosting logs and retention settings before publication.</p></section>
    <section><h2>Privacy requests</h2><p>Final contact details, data access/export procedures, deletion steps and applicable regional rights are pending operator and legal review. This draft is not a substitute for the final release policy.</p></section>
  </LegalPage>;
}
