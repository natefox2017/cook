import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const { vars } = JSON.parse(readFileSync(new URL('wrangler.jsonc', root), 'utf8'));
// Build-time sitemap/metadata and deployed runtime use the same public settings.
const result = spawnSync(process.execPath, ['node_modules/@opennextjs/cloudflare/dist/cli/index.js', 'build'], {
  cwd: fileURLToPath(root),
  env: { ...process.env, ...vars },
  stdio: 'inherit',
});
if (result.error) throw result.error;
process.exit(result.status ?? 1);
