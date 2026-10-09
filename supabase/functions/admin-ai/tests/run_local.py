# Developer: gengyun
# Purpose: Exercise the complete migration chain and real admin AI HTTP in an isolated local stack.
import argparse
import base64
import hashlib
import hmac
import json
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import time
import urllib.error
import urllib.request

MODULE = Path(__file__).resolve().parents[1]
ROOT = MODULE.parents[2]
CHECKS = []
BASE_PORT = 57821


def check(name, condition):
    if not condition:
        raise RuntimeError("FAIL: " + name)
    CHECKS.append(name)
    print("PASS: " + name, flush=True)


def sql(statement):
    result = subprocess.run(["docker", "exec", "-i", "supabase_db_" + PROJECT,
                             "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"],
                            input=statement, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError("Local SQL failed: " + result.stderr[-2000:])
    return result.stdout.strip()


def call(path, body=None, token=None, method="POST", key=None):
    headers = {"Content-Type": "application/json", "apikey": key or STATUS["ANON_KEY"]}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(f"http://127.0.0.1:{BASE_PORT}" + path, data=data, headers=headers, method=method)
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args):
            return None
    try:
        response = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect).open(request, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read().decode()
        check("HTTP response never contains synthetic key", "synthetic-provider-key" not in raw)
        return response.code, json.loads(raw) if raw else None


def api(path, body=None, role="owner", method="POST"):
    return call("/functions/v1/admin-ai" + path, body, TOKENS.get(role), method)


def body(**changes):
    return dict({"name": "Synthetic Fixture", "baseUrl": "https://example.com/v1", "model": "fixture-model",
                 "apiKey": "synthetic-provider-key", "active": True}, **changes)


def jwt(role):
    def enc(value):
        return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).decode().rstrip("=")
    unsigned = enc({"alg": "HS256", "typ": "JWT"}) + "." + enc({"role": role, "exp": int(time.time()) + 3600})
    signature = hmac.new(STATUS["JWT_SECRET"].encode(), unsigned.encode(), hashlib.sha256).digest()
    return unsigned + "." + base64.urlsafe_b64encode(signature).decode().rstrip("=")


def fixtures():
    global TOKENS
    TOKENS = {role: secrets.token_hex(32) for role in ("owner", "admin", "operator", "readonly", "expired", "revoked")}
    for role, token in TOKENS.items():
        digest = hashlib.sha256(token.encode()).hexdigest()
        account_role = role if role in ("owner", "admin", "operator", "readonly") else "admin"
        expires = "now() - interval '1 minute'" if role == "expired" else "now() + interval '1 hour'"
        revoked = "now()" if role == "revoked" else "null"
        sql(f"with a as (insert into public.admin_accounts(username,password_hash,role) values ('fixture-{role}','synthetic-unused','{account_role}') returning id) "
            f"insert into public.admin_sessions(admin_id,token_hash,created_at,expires_at,revoked_at) select id,'{digest}',now()-interval '1 hour',{expires},{revoked} from a;")


def http_checks():
    fixtures()
    for role in (None, "operator", "readonly", "expired", "revoked"):
        expected = 403 if role in ("operator", "readonly") else 401
        for path, method, payload in [("/providers", "GET", None), ("/usage", "GET", None),
                                      ("/providers", "POST", body()), ("/providers/test", "POST", body()),
                                      ("/providers/00000000-0000-4000-8000-000000000001", "PUT", body()),
                                      ("/providers/00000000-0000-4000-8000-000000000001", "DELETE", None)]:
            check(f"{role or 'missing'} {method} {path} returns {expected}", api(path, payload, role, method)[0] == expected)
    check("denied roles never create providers", sql("select count(*) from public.ai_providers") == "0")
    for role in ("owner", "admin"):
        check(role + " lists providers", api("/providers", role=role, method="GET")[0] == 200)
        check(role + " reads usage", api("/usage", role=role, method="GET")[0] == 200)
        check("create rejects missing key", api("/providers", body(apiKey=""), role)[0] == 400)
        code, created = api("/providers", body(name=role + " fixture"), role)
        check(role + " creates provider and one model", code == 200 and created["apiKeyConfigured"] and created["model"] == "fixture-model")
        provider = created["id"]
        model = sql(f"select id from public.ai_models where provider_id='{provider}'")
        secret = sql(f"select secret_ref from public.ai_providers where id='{provider}'")
        check("new key stores v2 envelope", sql(f"select key_version from public.ai_secrets where secret_ref='{secret}'") == "2")
        check("new key is not plaintext", sql(f"select ciphertext like '%synthetic-provider-key%' from public.ai_secrets where secret_ref='{secret}'") == "f")
        code, edited = api("/providers/" + provider, body(apiKey="", active=False, model="renamed"), role, "PUT")
        check("blank-key edit and safe rename succeed", code == 200 and edited["model"] == "renamed" and not edited["active"])
        check("rename preserves model identity and blank key", sql(f"select id from public.ai_models where provider_id='{provider}'") == model and sql(f"select secret_ref from public.ai_providers where id='{provider}'") == secret)
        check("rotation succeeds", api("/providers/" + provider, body(model="renamed"), role, "PUT")[0] == 200)
        rotated = sql(f"select secret_ref from public.ai_providers where id='{provider}'")
        check("rotation inserts fresh ref and retains old row", rotated != secret and sql(f"select count(*) from public.ai_secrets where secret_ref='{secret}'") == "1")
        check("saved v2 probe uses stored URL despite private caller override", api("/providers/test", {"providerId": provider, "baseUrl": "http://127.0.0.1", "model": "attacker", "apiKey": "ignored"}, role)[0] == 200)
        check("one-time private endpoint is rejected", api("/providers/test", body(baseUrl="https://127.0.0.1"), role)[0] == 400)
        check("one-time HTTPS probe executes", api("/providers/test", body(), role)[0] == 200)
        sql(f"insert into public.ai_routes(route_key,fallback_model_ids) values ('fixture-{role}',array['{model}'::uuid]);")
        check("fallback prevents delete via HTTP", api("/providers/" + provider, role=role, method="DELETE")[0] == 409)
        check("fallback prevents rename via HTTP", api("/providers/" + provider, body(model="blocked"), role, "PUT")[0] == 409)
        sql(f"delete from public.ai_routes where route_key='fixture-{role}';")
        check("unreferenced delete succeeds", api("/providers/" + provider, role=role, method="DELETE")[0] == 200)
        check("delete retains rotated secret", sql(f"select count(*) from public.ai_secrets where secret_ref='{rotated}'") == "1")

    sql("insert into public.ai_secrets(secret_ref,ciphertext,nonce,key_version) values ('legacy-v1','opaque-v1-cipher','opaque-v1-nonce',1);")
    legacy = sql("insert into public.ai_providers(name,base_url,secret_ref) values ('legacy','https://example.com/v1','legacy-v1') returning id;").splitlines()[0]
    sql(f"insert into public.ai_models(provider_id,display_name,upstream_model_id) values ('{legacy}','Legacy','legacy-model');")
    check("saved v1 probe rejects unsupported version", api("/providers/test", {"providerId": legacy})[0] == 409)
    check("legacy blank edit succeeds", api("/providers/" + legacy, body(model="legacy-model", apiKey=""), method="PUT")[0] == 200)
    check("legacy envelope remains byte-for-byte", sql("select ciphertext||','||nonce||','||key_version from public.ai_secrets where secret_ref='legacy-v1'") == "opaque-v1-cipher,opaque-v1-nonce,1")
    check("explicit legacy replacement succeeds", api("/providers/" + legacy, body(model="legacy-model"), method="PUT")[0] == 200)
    check("replacement keeps legacy row", sql("select ciphertext||','||nonce||','||key_version from public.ai_secrets where secret_ref='legacy-v1'") == "opaque-v1-cipher,opaque-v1-nonce,1")
    for role in ("anon", "authenticated"):
        for rpc, params in [("admin_ai_save_provider", {"p_provider_id": None,"p_name": "denied", "p_base_url": "https://example.com", "p_model": "denied", "p_active": True}),
                            ("admin_ai_delete_provider", {"p_provider_id": legacy})]:
            code, _ = call("/rest/v1/rpc/" + rpc, params, jwt(role))
            check(role + " cannot directly execute " + rpc, code in (401, 403, 404))

    # Hold an uncommitted JSON/array reference. Delete must wait, then reject
    # after the writer commits; fallback arrays have no FK to serialize this.
    code, raced = api("/providers", body())
    provider = raced["id"]
    model = sql(f"select id from public.ai_models where provider_id='{provider}'")
    for kind in ("fallback", "attempted"):
        statement = (f"insert into public.ai_routes(route_key,fallback_model_ids) values ('race',array['{model}'::uuid]);" if kind == "fallback" else
                     f"insert into public.ai_usage_events(request_id,route_key,status,attempted_models) values ('race','race','error',jsonb_build_array('{model}'));")
        writer = subprocess.Popen(["docker", "exec", "-i", "supabase_db_" + PROJECT,
                                   "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-At"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        writer.stdin.write("begin; " + statement + " select 'WRITER_READY'; select pg_sleep(2); commit;\n")
        writer.stdin.close()
        check(kind + " writer is active", writer.stdout.readline().strip() == "BEGIN" and bool(writer.stdout.readline()) and writer.stdout.readline().strip() == "WRITER_READY")
        started = time.monotonic()
        code, _ = api("/providers/" + provider, method="DELETE")
        check(kind + " concurrent delete waits and rejects", code == 409 and time.monotonic() - started > 1)
        writer.wait(timeout=10)
        check(kind + " reference and provider survive", writer.returncode == 0 and sql(f"select count(*) from public.ai_providers where id='{provider}'") == "1")
        sql("delete from public.ai_routes where route_key='race'; delete from public.ai_usage_events where request_id='race';")
    check("provider deletes after references removed", api("/providers/" + provider, method="DELETE")[0] == 200)


def main():
    global WORK, PROJECT, STATUS
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing", help="Use an already prepared isolated workdir for iteration")
    args = parser.parse_args()
    PROJECT = "recipe-ai-" + secrets.token_hex(5)
    WORK = Path(args.existing).resolve() if args.existing else ROOT / ".tmp" / PROJECT
    WORK.mkdir(parents=True, mode=0o700, exist_ok=True)
    if not args.existing:
        subprocess.run(["supabase", "init", "--workdir", str(WORK)], check=True, capture_output=True)
        config = WORK / "supabase/config.toml"
        contents = re.sub(r'project_id = "[^"]+"', 'project_id = "' + PROJECT + '"', config.read_text())
        for old, new in [("54321","57821"),("54322","57822"),("54320","57820"),("54323","57823"),("54324","57824"),("54327","57827"),("54329","57829")]:
            contents = contents.replace(old,new)
        config.write_text(contents + "\n[functions.admin-ai]\nverify_jwt = false\n")
        shutil.copytree(ROOT / "supabase/migrations", WORK / "supabase/migrations")
    else:
        PROJECT = re.search(r'project_id = "([^"]+)"', (WORK / "supabase/config.toml").read_text()).group(1)
    shutil.copytree(ROOT / "supabase/functions", WORK / "supabase/functions", dirs_exist_ok=True)
    server = None
    try:
        if not args.existing:
            with (WORK / "startup.log").open("w") as log:
                subprocess.run(["supabase", "start", "--workdir", str(WORK), "-x",
                                "realtime,imgproxy,mailpit,postgres-meta,studio,logflare,vector,supavisor"], check=True, stdout=log, stderr=log)
        STATUS = json.loads(subprocess.check_output(["supabase", "status", "--workdir", str(WORK), "-o", "json"], stderr=subprocess.DEVNULL))
        check("stack is isolated on loopback", STATUS["API_URL"] == f"http://127.0.0.1:{BASE_PORT}")
        check("complete 18 migration chain applied", sql("select count(*) from supabase_migrations.schema_migrations") == "18")
        tap = sql((ROOT / "supabase/tests/database/admin_ai_provider_transactions.sql").read_text())
        (WORK / "pgtap.log").write_text(tap)
        check("all 44 pgTAP assertions pass", "not ok" not in tap and "1..44" in tap)
        env_file = WORK / "edge.env"
        env_file.touch(mode=0o600)
        env_file.write_text("COOKAPP_AI_SECRET_KEY_V2=" + base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=") + "\n")
        with (WORK / "edge.log").open("w") as log:
            server = subprocess.Popen(["supabase", "functions", "serve", "--workdir", str(WORK), "--env-file", str(env_file)], stdout=log, stderr=log)
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError("Local Edge exited; inspect private log")
                try:
                    code, _ = call("/functions/v1/admin-ai/providers", method="GET")
                    if code == 401:
                        break
                except (urllib.error.URLError, json.JSONDecodeError):
                    pass
                time.sleep(0.2)
            else:
                raise RuntimeError("Local Edge did not become ready")
            http_checks()
        source_files = list(MODULE.glob("*.ts")) + [ROOT / "supabase/functions/_shared/ai-secret.ts", ROOT / "supabase/migrations/20261009160000_admin_ai_provider_transactions.sql"]
        (WORK / "report.json").write_text(json.dumps({"checks": CHECKS, "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files},
            "git_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "limitations": "Synthetic local database/admin sessions/keys and public example.com negative probes. No production deployment, real provider credentials, or external v1 worker resolver verification."}, indent=2) + "\n")
    finally:
        if server:
            server.terminate()
            server.wait(timeout=10)
        if not args.existing:
            subprocess.run(["supabase", "stop", "--project-id", PROJECT, "--no-backup"], check=True, capture_output=True)
    print(f"PASS: {len(CHECKS)} checks. Private report: {WORK}")


if __name__ == "__main__":
    main()
