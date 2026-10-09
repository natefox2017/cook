// Developer: gengyun
// Purpose: Run repository SQL tests against disposable in-memory PostgreSQL with real pgTAP and PGMQ.
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { pgtap } from '@electric-sql/pglite-pgtap';
import { pgmq } from '@electric-sql/pglite-pgmq';

const root = new URL('../../', import.meta.url);
const sql = async (path) => readFile(new URL(path, root), 'utf8');
// No connection string or persistence path is accepted. Production cannot be a target.
const db = new PGlite({ extensions: { pgtap, pgmq } });
try {
  console.log((await db.query('select version()')).rows[0].version);
  await db.exec('create extension pgtap; create extension pgmq;');
  console.log('Extensions:', (await db.query('select extname, extversion from pg_extension order by extname')).rows);
  await db.exec(await sql('tests/isolated/bootstrap.sql'));
  const migrations = [
    '20261007_user_snapshots.sql',
    '20261008024843_user_snapshot_revision.sql',
    '20261008024927_guard_user_snapshot_revision_updates.sql',
    '20261008030120_bind_snapshot_writes_to_owner.sql',
    '20261008050000_restrict_user_snapshot_writes_to_rpc.sql',
    '20261008103818_restrict_untrusted_security_definer_rpcs.sql',
    '20261009120000_fix_admin_bootstrap_owner_ambiguous_id.sql',
    '20261009121000_restrict_admin_bootstrap_owner_execution.sql',
    '20261008155000_recipe_import_jobs_v1.sql',
    '20261008195255_preserve_recipe_import_source_url.sql',
    '20261008200000_recipe_import_artifacts_v1.sql',
  ];
  for (const file of migrations) {
    await db.exec(await sql(`migrations/${file}`));
    console.log(`Applied ${file}`);
  }
  for (const file of [
    'tests/security_definer_function_privileges.test.sql',
    'tests/database/admin_bootstrap_owner.sql',
    'tests/database/recipe_import_jobs_v1.sql',
    'tests/database/snapshot_artifact_boundaries.sql',
  ]) {
    console.log(`\n${file}`);
    const results = await db.exec(await sql(file));
    const lines = results.flatMap((result) => result.rows.flatMap((row) => Object.values(row)))
      .filter((value) => typeof value === 'string')
      .flatMap((value) => value.split('\n'));
    for (const line of lines) console.log(line);
    assert(!lines.some((line) => /^(not ok|Bail out!|# Looks like)/.test(line)), `${file} failed`);
    const plan = lines.find((line) => /^1\.\.[0-9]+$/.test(line));
    assert(plan, `${file} has no TAP plan`);
    assert.equal(lines.filter((line) => /^ok [0-9]+/.test(line)).length, Number(plan.slice(3)), `${file} incomplete`);
  }
  console.log('\nPASS: all selected SQL suites; legacy bodies, HTTP Auth/Storage and deployment are not tested.');
} finally {
  await db.close();
}
