// Developer: gengyun
// Purpose: Verify DEV-282 sharing migration replay and complete rollback without any hosted database.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { pgtap } from '@electric-sql/pglite-pgtap';

const root = new URL('../../', import.meta.url);
const sql = (path) => readFile(new URL(path, root), 'utf8');
const shareTable = 'public.recipe_shared_snapshots';
const shareFunction = 'public.create_recipe_share_once(uuid,jsonb,text,text)';

async function sharingAssertions(db) {
  const results = await db.exec(await sql('tests/isolated/fixtures/recipe_shared_snapshots_v1.sql'));
  const lines = results.flatMap((result) => result.rows.flatMap((row) => Object.values(row)))
    .filter((value) => typeof value === 'string')
    .flatMap((value) => value.split('\n'));
  assert(!lines.some((line) => /^(not ok|Bail out!|# Looks like)/.test(line)), lines.join('\n'));
  assert(lines.includes('1..32'), 'original sharing fixture must keep its 32-assertion plan');
  assert.equal(lines.filter((line) => /^ok [0-9]+/.test(line)).length, 32);
}

async function shareSecurity(db) {
  return (await db.query(`
    select
      (select relrowsecurity from pg_class where oid = '${shareTable}'::regclass) as rls,
      has_table_privilege('anon', '${shareTable}', 'SELECT') as guest_select,
      has_table_privilege('authenticated', '${shareTable}', 'INSERT') as client_insert,
      has_table_privilege('authenticated', '${shareTable}', 'UPDATE') as client_update,
      has_table_privilege('authenticated', '${shareTable}', 'DELETE') as client_delete,
      has_function_privilege('anon', '${shareFunction}', 'EXECUTE') as guest_execute,
      has_function_privilege('authenticated', '${shareFunction}', 'EXECUTE') as client_execute,
      has_function_privilege('service_role', '${shareFunction}', 'EXECUTE') as service_execute,
      (select jsonb_agg(jsonb_build_object(
        'name', policyname, 'roles', roles, 'command', cmd,
        'using', qual, 'check', with_check
      ) order by policyname) from pg_policies
       where schemaname = 'public' and tablename = 'recipe_shared_snapshots') as policies
  `)).rows[0];
}

test('sharing migration preserves replayed data and removes all owned objects on disposable rollback', async () => {
  const files = (await readdir(new URL('migrations/', root)))
    .filter((file) => /^\d{14}_recipe_shared_snapshots_v1\.sql$/.test(file));
  assert.equal(files.length, 1, 'exactly one CLI-generated sharing migration is required');
  const migration = await sql(`migrations/${files[0]}`);
  const rollback = await sql('tests/isolated/recipe-share-rollback.sql');
  // No connection string or persistence path is accepted; a hosted DB cannot be a target.
  const db = new PGlite({ extensions: { pgtap } });
  try {
    await db.exec('create extension pgtap;');
    await db.exec(await sql('tests/isolated/bootstrap.sql'));
    await db.exec(await sql('migrations/20261007_user_snapshots.sql'));
    const privateObjects = (await db.query(`
      select 'auth.users'::regclass::oid as auth_oid,
        'public.user_snapshots'::regclass::oid as snapshot_oid,
        (select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p
         where schemaname = 'public' and tablename = 'user_snapshots') as policies
    `)).rows[0];
    await db.exec(migration);
    await sharingAssertions(db);
    const security = await shareSecurity(db);
    assert.deepEqual({ ...security, policies: undefined }, {
      rls: true, guest_select: false, client_insert: false, client_update: false,
      client_delete: false, guest_execute: false, client_execute: false,
      service_execute: true, policies: undefined,
    });
    assert.equal(security.policies.length, 3);

    // Keep a distinct owner outside the original fixture's rollback transaction.
    await db.exec(`
      insert into auth.users(id) values ('66666666-6666-4666-8666-666666666666');
      insert into public.user_snapshots(user_id, payload, client_updated_at)
      values ('66666666-6666-4666-8666-666666666666', '{"private":"retained"}', now());
      insert into public.recipe_shared_snapshots (
        owner_id, source_recipe_id, source_client_updated_at, opaque_slug,
        share_version, scope, sanitized_snapshot, idempotency_key, request_hash
      ) values (
        '66666666-6666-4666-8666-666666666666',
        '77777777-7777-4777-8777-777777777777', now(), repeat('z',43),
        7, 'summaryAndSource', '{"ingredients":[],"steps":[]}',
        '88888888-8888-4888-8888-888888888888', repeat('f',64)
      );
    `);
    const before = (await db.query(`select * from ${shareTable}`)).rows;
    await db.exec(migration);
    assert.deepEqual((await db.query(`select * from ${shareTable}`)).rows, before);
    assert.deepEqual(await shareSecurity(db), security);

    const owned = (await db.query(`
      select (select array_agg(indexname order by indexname) from pg_indexes
        where schemaname = 'public' and tablename = 'recipe_shared_snapshots') as indexes
    `)).rows[0];
    assert(owned.indexes.length >= 4);
    await db.exec(rollback);
    await db.exec(rollback);
    const removed = (await db.query(`
      select to_regclass('${shareTable}') as share_table,
        to_regprocedure('${shareFunction}') as share_rpc,
        (select count(*)::int from pg_policies where schemaname = 'public'
         and tablename = 'recipe_shared_snapshots') as policies
    `)).rows[0];
    assert.deepEqual(removed, { share_table: null, share_rpc: null, policies: 0 });
    for (const index of owned.indexes) {
      assert.equal((await db.query('select to_regclass($1) as index', [`public.${index}`])).rows[0].index, null);
    }
    assert.deepEqual((await db.query(`
      select 'auth.users'::regclass::oid as auth_oid,
        'public.user_snapshots'::regclass::oid as snapshot_oid,
        (select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p
         where schemaname = 'public' and tablename = 'user_snapshots') as policies
    `)).rows[0], privateObjects);
    assert.deepEqual((await db.query('select payload from public.user_snapshots')).rows,
      [{ payload: { private: 'retained' } }]);
    assert.equal((await db.query('select count(*)::int as count from auth.users')).rows[0].count, 1);

    await db.exec(migration);
    assert.deepEqual(await shareSecurity(db), security);
    await sharingAssertions(db);
    console.log('LOCAL DB PASS: fresh/reapply sharing 32 + 32 pgTAP assertions; replay/rollback/private preservation.');
  } finally {
    await db.close();
  }
});
