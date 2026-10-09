# Developer: gengyun
# Purpose: Reproduce the observed owner bug and verify patched SQL plus real Edge HTTP in a disposable stack.

from concurrent.futures import ThreadPoolExecutor
import hashlib
import hmac
import json
from pathlib import Path
import secrets
import shutil
import subprocess
import time
import urllib.error
import urllib.request

MODULE = Path(__file__).resolve().parents[1]
ROOT = MODULE.parents[2]
PROJECT = "recipe-rc-" + secrets.token_hex(5)
WORK = ROOT / ".tmp" / PROJECT
OWNER_A = "00000000-0000-4000-8000-000000000001"
OWNER_B = "00000000-0000-4000-8000-000000000002"
BEARER = secrets.token_hex(32)
SIGNING = secrets.token_hex(32)
CHECKS = []


def check(name, condition):
    if not condition:
        raise RuntimeError("FAIL: " + name)
    CHECKS.append(name)
    print("PASS: " + name, flush=True)


def sql(text):
    command = ["docker", "exec", "-i", "supabase_db_" + PROJECT,
               "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"]
    try:
        return subprocess.check_output(command, input=text, text=True, stderr=subprocess.STDOUT).strip()
    except subprocess.CalledProcessError as error:
        raise RuntimeError("Local SQL failed: " + error.output[-2000:]) from error


def call(path, body=None, authorization=None, signature=None, method="POST", key=None):
    headers = {"Content-Type": "application/json", "apikey": key or STATUS["PUBLISHABLE_KEY"]}
    if authorization is not None:
        headers["Authorization"] = authorization
    if signature is not None:
        headers["X-RevenueCat-Webhook-Signature"] = signature
    data = body.encode() if isinstance(body, str) else json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("http://127.0.0.1:56821" + path, data=data, method=method, headers=headers)
    # Explicit loopback URL, no proxy and no redirects: local credentials cannot leave the host.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args):
            return None
    try:
        response = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect).open(req, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read()
        try:
            value = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            value = None
        return response.code, value


def params(owner, event_id):
    return {"p_user_id": owner, "p_event_type": "INITIAL_PURCHASE", "p_product_id": "fixture.monthly",
            "p_entitlement_id": "pro", "p_status": "active", "p_store": "app_store",
            "p_environment": "sandbox", "p_expires_at": None, "p_will_renew": True,
            "p_revenuecat_app_user_id": owner, "p_rc_event_id": event_id,
            "p_raw_event": {"event_timestamp_ms": 1700000000000, "price": 4.99,
                            "price_in_purchased_currency": 4.99, "currency": "USD"}}


def rpc(owner, event_id):
    return call("/rest/v1/rpc/upsert_subscription_from_revenuecat", params(owner, event_id),
                "Bearer " + STATUS["SERVICE_ROLE_KEY"], key=STATUS["SERVICE_ROLE_KEY"])


def payment(owner, event_id):
    definition = (MODULE / "tests/fixtures/observed-rpcs.sql").read_text()
    import re
    declaration = next(line for line in definition.splitlines() if line.startswith("CREATE OR REPLACE FUNCTION public.upsert_payment_transaction("))
    args = {name: None for name in re.findall(r"\b(p_[a-z_]+) ", declaration)}
    args.update({"p_user_id": owner, "p_event_type": "INITIAL_PURCHASE", "p_status": "active",
                 "p_provider_source": "revenuecat", "p_provider_event_id": event_id,
                 "p_environment": "sandbox", "p_store": "app_store"})
    return call("/rest/v1/rpc/upsert_payment_transaction", args,
                "Bearer " + STATUS["SERVICE_ROLE_KEY"], key=STATUS["SERVICE_ROLE_KEY"])


def owner_pair(event_id):
    return sql("select p.user_id::text || ',' || t.user_id::text from public.purchase_events p "
               "join public.payment_transactions t on t.purchase_event_id=p.id "
               "where p.rc_event_id='" + event_id + "';")


def signature(raw, secret=SIGNING, timestamp=None):
    timestamp = str(int(time.time()) if timestamp is None else timestamp)
    digest = hmac.new(secret.encode(), (timestamp + "." + raw).encode(), hashlib.sha256).hexdigest()
    return "t=" + timestamp + ",v1=" + digest


def event(owner=OWNER_A, event_id=None, kind="INITIAL_PURCHASE", **extra):
    return {"event": dict({"id": event_id or secrets.token_hex(8), "type": kind,
                           "app_user_id": owner, "product_id": "fixture.monthly", "store": "APP_STORE",
                           "environment": "SANDBOX", "event_timestamp_ms": 1700000000000}, **extra)}


def webhook(body, sig=True, authorization="correct", method="POST"):
    raw = body if isinstance(body, str) else json.dumps(body)
    auth = "Bearer " + BEARER if authorization == "correct" else authorization
    header = signature(raw) if sig is True else sig
    return call("/functions/v1/revenuecat-webhook", raw, auth, header, method)


def start_server(signed, configured=True):
    env_file = WORK / "webhook.env"
    env_file.touch(mode=0o600)
    env_file.write_text(("REVENUECAT_WEBHOOK_SECRET=" + BEARER + "\n" if configured else "") +
                        ("REVENUECAT_WEBHOOK_SIGNING_SECRET=" + SIGNING + "\n" if signed else ""))
    log = (WORK / ("edge-misconfigured.log" if not configured else "edge-signed.log" if signed else "edge-bearer.log")).open("w")
    process = subprocess.Popen(["supabase", "functions", "serve", "--workdir", str(WORK),
                                "--env-file", str(env_file)], stdout=log, stderr=log)
    try:
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError("Local Edge serve process exited; inspect private edge log")
            try:
                status, _ = webhook(event(kind="TEST"), sig=signed)
                if status == (200 if configured else 500):
                    return process, log
            except urllib.error.URLError:
                pass
            time.sleep(0.2)
        raise RuntimeError("Local Edge handler did not become ready; inspect private edge log")
    except BaseException:
        process.terminate()
        process.wait(timeout=10)
        log.close()
        raise


def stop_server(server):
    process, log = server
    process.terminate()
    process.wait(timeout=10)
    log.close()


def sql_checks():
    check("observed RPC creates initial fixture payment", rpc(OWNER_A, "observed-owner-bug")[0] == 200)
    check("observed RPC accepts mismatched-owner duplicate", rpc(OWNER_B, "observed-owner-bug")[0] == 200)
    if owner_pair("observed-owner-bug") != OWNER_A + "," + OWNER_B:
        raise RuntimeError("Expected baseline owner bug was not reproduced")
    print("REPRODUCED FAIL: observed live RPC moves payment to B while purchase event remains A", flush=True)
    sql("truncate public.payment_transactions, public.purchase_events, public.subscriptions;")
    sql((ROOT / "supabase/migrations/20261009150000_revenuecat_event_owner_binding.sql").read_text())
    check("patched RPC creates initial payment", rpc(OWNER_A, "patched-event")[0] == 200)
    before = sql("select row_to_json(t) from public.payment_transactions t where provider_event_id='patched-event';")
    check("same-owner duplicate succeeds", rpc(OWNER_A, "patched-event")[0] == 200)
    check("same-owner duplicate has no payment side effects", before == sql("select row_to_json(t) from public.payment_transactions t where provider_event_id='patched-event';"))
    altered = params(OWNER_A, "patched-event")
    altered.update({"p_status": "expired", "p_event_type": "EXPIRATION", "p_raw_event": {"price": 999}})
    code, _ = call("/rest/v1/rpc/upsert_subscription_from_revenuecat", altered,
                   "Bearer " + STATUS["SERVICE_ROLE_KEY"], key=STATUS["SERVICE_ROLE_KEY"])
    check("same-owner duplicate altered payload is acknowledged", code == 200)
    check("altered duplicate never modifies payment contents", before == sql("select row_to_json(t) from public.payment_transactions t where provider_event_id='patched-event';"))
    code, value = rpc(OWNER_B, "patched-event")
    check("different-owner duplicate rejects with 42501", code == 403 and value["code"] == "42501")
    check("rejected duplicate preserves payment owner", owner_pair("patched-event") == OWNER_A + "," + OWNER_A)
    check("unassigned payment can be recorded", payment(None, "unassigned-event")[0] == 200)
    check("unassigned payment may acquire its first owner", payment(OWNER_A, "unassigned-event")[0] == 200)
    check("assigned payment cannot become unassigned", payment(None, "unassigned-event")[0] == 403)
    check("assigned payment cannot transfer to B", payment(OWNER_B, "unassigned-event")[0] == 403)
    check("NULL and B attempts preserve payment A", sql("select user_id from public.payment_transactions where provider_event_id='unassigned-event';") == OWNER_A)
    for index in range(5):
        event_id = "payment-race-" + str(index)
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(payment, owner, event_id) for owner in (OWNER_A, OWNER_B)]
            results = [future.result() for future in futures]
        check("payment upsert owner race has one success and one denial", sorted(result[0] for result in results) == [200, 403])
        check("payment upsert race keeps a single assigned row", sql("select count(*) from public.payment_transactions where provider_event_id='" + event_id + "' and user_id is not null;") == "1")
    for index in range(5):
        event_id = "rpc-race-" + str(index)
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(rpc, owner, event_id) for owner in (OWNER_A, OWNER_B)]
            results = [future.result() for future in futures]
        check("RPC owner race has one success and one denial", sorted(result[0] for result in results) == [200, 403])
        pair = owner_pair(event_id).split(",")
        check("RPC owner race preserves consistent event/payment owner", len(pair) == 2 and pair[0] == pair[1])
    code, _ = call("/rest/v1/rpc/upsert_subscription_from_revenuecat", params(OWNER_A, "anon"))
    check("anonymous direct RPC bypass is denied", code in (401, 403))


def http_checks():
    body = event(event_id="header-boundary")
    for auth in (None, "Bearer wrong", "wrong", "bearer " + BEARER):
        check("invalid or absent bearer is rejected", webhook(body, authorization=auth)[0] == 401)
    check("missing signature is rejected when signing is configured", webhook(body, sig=None)[0] == 401)
    raw = json.dumps(body)
    check("wrong signing secret is rejected", webhook(raw, sig=signature(raw, secret=BEARER))[0] == 401)
    check("stale signature is rejected", webhook(raw, sig=signature(raw, timestamp=int(time.time()) - 301))[0] == 401)
    check("modified raw body invalidates signature", webhook(raw + " ", sig=signature(raw))[0] == 401)
    check("method GET cannot mutate state", webhook(body, method="GET")[0] == 405)
    check("auth failures never reach DB", sql("select count(*) from public.purchase_events where rc_event_id='header-boundary';") == "0")
    check("invalid JSON returns 400", webhook("{")[0] == 400)
    for bad in (None, [], {"event": []}, {"event": "bad"}):
        check("invalid event shape returns 400", webhook(json.dumps(bad))[0] == 400)
    missing = event(); del missing["event"]["id"]
    check("missing event ID cannot bypass deduplication", webhook(missing)[0] == 400)
    check("oversized signed body is bounded", webhook(" " * 65537)[0] == 413)
    check("out-of-range date does not crash handler", webhook(event(expiration_at_ms=1e30))[0] == 200)
    check("unknown event remains forward-compatible", webhook(event(kind="FUTURE_EVENT"))[1]["ignored"] is True)
    check("transfer event is explicitly ignored", webhook(event(kind="TRANSFER"))[1]["ignored"] is True)
    check("unmapped anonymous identity is skipped", webhook(event(owner="$RCAnonymousID:fixture"))[1]["reason"] == "unresolvable_user_id")
    check("anonymous current ID can resolve original UUID", webhook(event(owner="$RCAnonymousID:fixture", original_app_user_id=OWNER_A))[0] == 200)
    check("current UUID is authoritative over another original UUID", webhook(event(owner=OWNER_B, event_id="original-boundary", original_app_user_id=OWNER_A))[0] == 200)
    check("original UUID cannot redirect another current user's payment", owner_pair("original-boundary") == OWNER_B + "," + OWNER_B)
    check("nonexistent user skips without creating payment", webhook(event(owner="00000000-0000-4000-8000-000000000099"))[1]["reason"] == "user_not_found")
    check("first delivery succeeds", webhook(event(event_id="http-replay"))[0] == 200)
    check("same-owner replay acknowledges duplicate", webhook(event(event_id="http-replay"))[1]["already_processed"] is True)
    check("known different-owner replay returns 409", webhook(event(owner=OWNER_B, event_id="http-replay"))[0] == 409)
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda _: webhook(event(event_id="http-race")), range(8)))
    check("eight concurrent same-owner deliveries succeed", all(result[0] == 200 for result in results))
    check("concurrent deliveries create one event and one payment", sql("select (select count(*) from public.purchase_events where rc_event_id='http-race') || ',' || (select count(*) from public.payment_transactions where provider_event_id='http-race');") == "1,1")
    for index in range(5):
        event_id = "http-owner-race-" + str(index)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda owner: webhook(event(owner=owner, event_id=event_id)), (OWNER_A, OWNER_B)))
        check("HTTP owner race has one success and one conflict", sorted(result[0] for result in results) == [200, 409])
        pair = owner_pair(event_id).split(",")
        check("HTTP owner race does not cross event/payment accounts", pair[0] == pair[1])
    check("newer expiration updates A only", webhook(event(event_id="newer-expiration", kind="EXPIRATION", event_timestamp_ms=1700000003000))[0] == 200)
    check("older renewal cannot reactivate A", webhook(event(event_id="older-renewal", kind="RENEWAL", event_timestamp_ms=1700000001000))[0] == 200)
    check("A expiration and B active state remain independent", sql("select string_agg(status,',' order by user_id) from public.subscriptions;") == "expired,active")


def main():
    global STATUS
    WORK.mkdir(parents=True, mode=0o700)
    subprocess.run(["supabase", "init", "--workdir", str(WORK)], check=True, capture_output=True)
    config = WORK / "supabase/config.toml"
    contents = config.read_text()
    for old, new in [("54321", "56821"), ("54322", "56822"), ("54320", "56820"), ("54323", "56823"), ("54324", "56824"), ("54327", "56827"), ("54329", "56829")]:
        contents = contents.replace(old, new)
    config.write_text(contents + "\n[functions.revenuecat-webhook]\nverify_jwt = false\n")
    shutil.copytree(MODULE, WORK / "supabase/functions/revenuecat-webhook")
    try:
        startup = WORK / "startup.log"; startup.touch(mode=0o600)
        with startup.open("w") as log:
            subprocess.run(["supabase", "start", "--workdir", str(WORK), "-x",
                            "realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"],
                           check=True, stdout=log, stderr=log)
        STATUS = json.loads(subprocess.check_output(["supabase", "status", "--workdir", str(WORK), "-o", "json"], stderr=subprocess.DEVNULL))
        if STATUS["API_URL"] != "http://127.0.0.1:56821":
            raise RuntimeError("Unexpected local endpoint")
        for filename in ("schema.sql", "observed-rpcs.sql", "grants.sql"):
            sql((MODULE / "tests/fixtures" / filename).read_text())
        sql("notify pgrst, 'reload schema';")
        time.sleep(0.5)
        sql_checks()
        server = start_server(False, configured=False)
        try:
            code, value = webhook(event(kind="TEST"), sig=None)
            check("missing server secret fails closed", code == 500 and value["error"] == "server_misconfigured")
        finally:
            stop_server(server)
        server = start_server(False)
        try:
            check("bearer-only compatibility accepts authenticated TEST", webhook(event(kind="TEST"), sig=None)[0] == 200)
        finally:
            stop_server(server)
        server = start_server(True)
        try:
            http_checks()
        finally:
            stop_server(server)
        files = ["index.ts", "webhook.ts", "deno.json", "deno.lock", "tests/fixtures/observed-rpcs.sql"]
        hashes = {name: hashlib.sha256((MODULE / name).read_bytes()).hexdigest() for name in files}
        migration = ROOT / "supabase/migrations/20261009150000_revenuecat_event_owner_binding.sql"
        hashes[migration.name] = hashlib.sha256(migration.read_bytes()).hexdigest()
        (WORK / "report.json").write_text(json.dumps({"checks": CHECKS, "source_sha256": hashes,
            "git_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "baseline_failure_reproduced": "purchase owner A / payment owner B on observed RPC duplicate",
            "limitations": "Local schema fixture and copied observed RPCs, not complete production schema/deployment or real payments."}, indent=2) + "\n")
    finally:
        subprocess.run(["supabase", "stop", "--project-id", PROJECT, "--no-backup"], check=True, capture_output=True)
    print(f"PASS: {len(CHECKS)} checks. Private logs/report: {WORK}")


if __name__ == "__main__":
    main()
