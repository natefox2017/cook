import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const standalone = path.join(root, '.next/standalone');
const target = path.join(root, 'dist/recipe-pals-site');
if (!existsSync(path.join(standalone, 'server.js'))) {
  throw new Error('Run npm run build before packaging. Expected standalone server is missing.');
}
await rm(target, { recursive: true, force: true });
await mkdir(target, { recursive: true });
await cp(standalone, target, {
  recursive: true,
  filter: source => !/^\.env(?:\.|$)/.test(path.basename(source)) && path.basename(source) !== '.git',
});
await cp(path.join(root, '.next/static'), path.join(target, '.next/static'), { recursive: true });
await cp(path.join(root, 'public'), path.join(target, 'public'), { recursive: true });
await cp(path.join(root, '.env.example'), path.join(target, '.env.example'));
await cp(path.join(root, 'run.sh'), path.join(target, 'run.sh'));
await writeFile(path.join(target, 'start.mjs'), `import { fileURLToPath } from 'node:url';
process.chdir(fileURLToPath(new URL('./', import.meta.url)));
process.env.HOSTNAME = process.env.RECIPE_PALS_BIND_HOST || '0.0.0.0';
await import('./server.js');
`);
const archive = path.join(root, 'dist/recipe-pals-site.tar.gz');
const result = spawnSync('tar', ['-czf', archive, '-C', path.dirname(target), path.basename(target)], { stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) throw new Error('Packaging failed. Ensure tar is installed.');
console.log(`Packaged ${archive}\nExtract, configure runtime variables, then run node start.mjs (Node 22+).`);
