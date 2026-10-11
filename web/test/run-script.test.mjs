import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, cp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

test('one-command script resolves its own directory, installs missing dependencies and never sources env', async () => {
  const temp = await mkdtemp(path.join(tmpdir(), 'recipe-run-'));
  try {
    const site = path.join(temp, 'web');
    const bin = path.join(temp, 'bin');
    await mkdir(site);
    await mkdir(bin);
    await cp(new URL('../run.sh', import.meta.url), path.join(site, 'run.sh'));
    await writeFile(path.join(site, '.env.example'), 'EXAMPLE=$(touch unsafe-marker)\n');
    await writeFile(path.join(bin, 'npm'), '#!/bin/sh\nprintf "%s\\n" "$*" >> npm-calls\nif [ "$1" = ci ]; then mkdir -p node_modules/next; fi\n', { mode: 0o755 });
    const options = { cwd: temp, env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, encoding: 'utf8' };
    const result = spawnSync('bash', [path.join(site, 'run.sh')], options);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(await readFile(path.join(site, 'npm-calls'), 'utf8'), 'ci --no-audit --no-fund\nrun dev\n');
    assert.equal(await readFile(path.join(site, '.env.local'), 'utf8'), 'EXAMPLE=$(touch unsafe-marker)\n');
    await assert.rejects(readFile(path.join(site, 'unsafe-marker')));
    assert.equal(spawnSync('bash', [path.join(site, 'run.sh'), 'invalid'], options).status, 2);
    assert.equal(spawnSync('bash', [path.join(site, 'run.sh'), '--help'], options).status, 0);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});
