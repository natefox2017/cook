# Developer: gengyun
# Purpose: Exercise real local Auth email/session flows and snapshot HTTP ownership/CAS without hosted access.

import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".tmp" / "auth-sync-local"
PROJECT = "recipe-auth-sync-" + secrets.token_hex(5)
MIGRATIONS = [
    "20261007_user_snapshots.sql",
    "20261008024843_user_snapshot_revision.sql",
    "20261008024927_guard_user_snapshot_revision_updates.sql",
    "20261008030120_bind_snapshot_writes_to_owner.sql",
    "20261008050000_restrict_user_snapshot_writes_to_rpc.sql",
]
CALLBACK = "cook://auth/callback"
CHECKS = []


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


def check(name, condition):
    if not condition:
        raise RuntimeError("FAIL: " + name)
    CHECKS.append(name)
    print("PASS: " + name, flush=True)


def request(url, method="GET", body=None, key=None, token=None):
    # No URL provided by email or environment may redirect the harness off loopback.
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "http" or parsed.hostname != "127.0.0.1" or parsed.port not in (56721, 56724):
        raise ValueError("Only literal HTTP loopback endpoints are permitted")
    headers = {"Content-Type": "application/json"}
    if key:
        headers["apikey"] = key
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        response = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect).open(req, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read()
        try:
            value = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            value = None
        return response.code, value, response.headers


class Client:
    def __init__(self, status):
        self.api = status["API_URL"]
        self.key = status["PUBLISHABLE_KEY"]
        self.session = None

    def call(self, path, method="GET", body=None):
        token = self.session["access_token"] if self.session else None
        return request(self.api + path, method, body, self.key, token)

    def login(self, email, password):
        code, session, _ = self.call(
            "/auth/v1/token?grant_type=password", "POST",
            {"email": email, "password": password},
        )
        check("password login returns a real session", code == 200 and bool(session.get("access_token")))
        self.session = session
        return session["user"]["id"]

    def save(self, owner, revision, payload):
        return self.call("/rest/v1/rpc/save_own_user_snapshot", "POST", {
            "target_user_id": owner,
            "expected_revision": revision,
            "snapshot_schema_version": 2,
            "snapshot_payload": payload,
            "snapshot_client_updated_at": datetime.now(timezone.utc).isoformat(),
        })

    def read(self, owner):
        return self.call("/rest/v1/user_snapshots?select=*&user_id=eq." + owner)


def latest_mail(status, email, previous_ids):
    for _ in range(30):
        _, listing, _ = request(status["MAILPIT_URL"] + "/api/v1/messages")
        for message in listing["messages"]:
            recipients = [entry["Address"] for entry in message["To"]]
            if message["ID"] not in previous_ids and email in recipients:
                _, detail, _ = request(status["MAILPIT_URL"] + "/api/v1/message/" + message["ID"])
                return detail
        time.sleep(0.2)
    raise RuntimeError("Local Mailpit did not receive the requested email")


def mail_ids(status):
    _, listing, _ = request(status["MAILPIT_URL"] + "/api/v1/messages")
    return {message["ID"] for message in listing["messages"]}


def verify_mail_link(status, mail):
    content = html.unescape(mail["HTML"])
    links = re.findall(r'href="([^"]+)"', content)
    link = next(link for link in links if "/auth/v1/verify?" in link)
    code, _, headers = request(link)
    check("email link verified by GoTrue", code == 303)
    location = headers["Location"]
    check("verified email redirects to app callback", location.startswith(CALLBACK + "?"))
    return urllib.parse.parse_qs(urllib.parse.urlsplit(location).query)["code"][0]


def challenge(verifier):
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()


def exchange(client, code, verifier):
    return client.call("/auth/v1/token?grant_type=pkce", "POST", {
        "auth_code": code, "code_verifier": verifier,
    })


def run_checks(status):
    a, a2, b, anonymous = [Client(status) for _ in range(4)]
    email_a, email_b = ["recipe-" + secrets.token_hex(5) + "@example.test" for _ in range(2)]
    password = secrets.token_urlsafe(24) + "Aa1!"
    for client, email in [(a, email_a), (b, email_b)]:
        verifier = secrets.token_urlsafe(48)
        before = mail_ids(status)
        code, value, _ = client.call("/auth/v1/signup?redirect_to=" + urllib.parse.quote(CALLBACK), "POST", {
            "email": email, "password": password,
            "code_challenge": challenge(verifier), "code_challenge_method": "s256",
        })
        check("signup waits for email confirmation", code == 200 and not value.get("access_token"))
        code, _, _ = client.call("/auth/v1/token?grant_type=password", "POST", {"email": email, "password": password})
        check("unconfirmed account cannot password-login", code == 400)
        auth_code = verify_mail_link(status, latest_mail(status, email, before))
        code, session, _ = exchange(client, auth_code, verifier)
        check("PKCE confirmation code exchanges for session", code == 200 and bool(session.get("access_token")))
        client.session = session
    owner_a, owner_b = a.session["user"]["id"], b.session["user"]["id"]
    check("A and B are distinct verified Auth users", owner_a != owner_b)
    check("second independent A client has same identity", a2.login(email_a, password) == owner_a)
    code, _, _ = a2.call("/auth/v1/token?grant_type=password", "POST", {"email": email_a, "password": "wrong-password"})
    check("wrong password is rejected", code == 400)

    before = mail_ids(status)
    # Respect GoTrue's configured one-second email send interval for this account.
    time.sleep(1.1)
    code, _, _ = a2.call("/auth/v1/otp?redirect_to=" + urllib.parse.quote(CALLBACK), "POST", {
        "email": email_a, "create_user": True,
        "code_challenge": challenge(secrets.token_urlsafe(48)), "code_challenge_method": "s256",
    })
    check("passwordless email request succeeds", code == 200)
    mail = latest_mail(status, email_a, before)
    token = re.search(r'Code: (\d+)', mail["HTML"]).group(1)
    code, _, _ = a2.call("/auth/v1/verify", "POST", {"email": email_a, "token": "0000000", "type": "email"})
    check("incorrect email OTP is rejected", code == 403)
    code, session, _ = a2.call("/auth/v1/verify", "POST", {"email": email_a, "token": token, "type": "email"})
    check("numeric email OTP returns signed-in session", code == 200 and session["user"]["id"] == owner_a)
    a2.session = session
    code, _, _ = a2.call("/auth/v1/verify", "POST", {"email": email_a, "token": token, "type": "email"})
    check("email OTP cannot be reused", code == 403)

    first_time = Client(status)
    first_email = "recipe-" + secrets.token_hex(5) + "@example.test"
    before = mail_ids(status)
    code, _, _ = first_time.call("/auth/v1/otp?redirect_to=" + urllib.parse.quote(CALLBACK), "POST", {
        "email": first_email, "create_user": True,
        "code_challenge": challenge(secrets.token_urlsafe(48)), "code_challenge_method": "s256",
    })
    check("first-time passwordless signup accepts request", code == 200)
    mail = latest_mail(status, first_email, before)
    token = re.search(r'Code: (\d+)', mail["HTML"]).group(1)
    code, session, _ = first_time.call("/auth/v1/verify", "POST", {
        "email": first_email, "token": token, "type": "email",
    })
    check("first-time numeric email OTP creates a session", code == 200 and bool(session.get("access_token")))
    check("first-time passwordless identity is separate from A/B", session["user"]["id"] not in (owner_a, owner_b))

    # This is protocol payload evidence, not RecipeStore merge/UI acceptance.
    payload = {"version": 2, "recipes": [], "groceries": [], "mealPlan": [],
               "collections": [], "collectionMemberships": [], "settings": {}, "deletedEntities": []}
    code, rows, _ = a.save(owner_a, 0, payload)
    check("first snapshot save returns revision 1", code == 200 and rows[0]["revision"] == 1)
    code, rows, _ = a2.read(owner_a)
    check("independent A client downloads exact snapshot", code == 200 and rows[0]["payload"] == payload)
    code, rows, _ = b.read(owner_a)
    check("B cannot read A snapshot", code == 200 and rows == [])
    code, _, _ = b.save(owner_a, 1, payload)
    check("B cannot write a snapshot addressed to A", code == 403)
    code, _, _ = anonymous.read(owner_a)
    check("anonymous snapshot read is denied", code in (401, 403))
    code, _, _ = anonymous.save(owner_a, 1, payload)
    check("anonymous snapshot RPC is denied", code in (401, 403))
    code, rows, _ = b.save(owner_b, 0, payload)
    check("B saves its own independent snapshot", code == 200 and rows[0]["revision"] == 1)
    code, rows, _ = a.read(owner_b)
    check("A cannot read B snapshot", code == 200 and rows == [])
    for method, body in [("PATCH", {"payload": {}}), ("DELETE", None)]:
        code, _, _ = a.call("/rest/v1/user_snapshots?user_id=eq." + owner_a, method, body)
        check("direct snapshot " + method + " is denied", code == 403)
    code, _, _ = a.call("/rest/v1/user_snapshots", "POST", {
        "user_id": owner_a, "payload": payload, "client_updated_at": datetime.now(timezone.utc).isoformat(),
    })
    check("direct snapshot INSERT is denied", code == 403)

    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(client.save, owner_a, 1, dict(payload, deletedEntities=[marker]))
                   for client, marker in [(a, "client-a"), (a2, "client-a2")]]
        results = [future.result() for future in futures]
    check("concurrent same-revision requests both complete", all(result[0] == 200 for result in results))
    check("concurrent CAS permits exactly one winner", sorted(len(result[1]) for result in results) == [0, 1])
    winner = next(result[1][0] for result in results if result[1])
    check("CAS winner advances revision exactly once", winner["revision"] == 2)
    code, rows, _ = a2.save(owner_a, 1, payload)
    check("stale revision retry is rejected without write", code == 200 and rows == [])
    code, rows, _ = a.read(owner_a)
    check("stale write preserves winner payload", code == 200 and rows[0]["payload"] == winner["payload"])
    code, rows, _ = a2.save(owner_a, 2, payload)
    check("latest revision retry succeeds", code == 200 and rows[0]["revision"] == 3)
    code, rows, _ = b.read(owner_b)
    check("A writes never alter B revision", code == 200 and rows[0]["revision"] == 1)

    before = mail_ids(status)
    time.sleep(1.1)
    verifier = secrets.token_urlsafe(48)
    code, _, _ = a.call("/auth/v1/recover?redirect_to=" + urllib.parse.quote(CALLBACK), "POST", {
        "email": email_a, "code_challenge": challenge(verifier), "code_challenge_method": "s256",
    })
    check("password recovery accepts email request", code == 200)
    auth_code = verify_mail_link(status, latest_mail(status, email_a, before))
    code, _, _ = exchange(a, auth_code, secrets.token_urlsafe(48))
    check("PKCE rejects a mismatched verifier", code == 400)
    code, session, _ = exchange(a, auth_code, verifier)
    check("persisted matching verifier completes recovery", code == 200 and session["user"]["id"] == owner_a)
    a.session = session
    new_password = secrets.token_urlsafe(24) + "Aa1!"
    code, _, _ = a.call("/auth/v1/user", "PUT", {"password": new_password})
    check("recovered session updates password", code == 200)
    code, _, _ = a2.call("/auth/v1/token?grant_type=password", "POST", {"email": email_a, "password": password})
    check("old password stops working after recovery", code == 400)
    check("new password retains account identity", a2.login(email_a, new_password) == owner_a)
    code, session, _ = a2.call("/auth/v1/token?grant_type=refresh_token", "POST", {"refresh_token": a2.session["refresh_token"]})
    check("refresh token returns same account identity", code == 200 and session["user"]["id"] == owner_a)
    a2.session = session
    code, _, _ = a2.call("/auth/v1/logout?scope=local", "POST")
    check("local-session signout succeeds", code == 204)
    code, _, _ = a2.call("/auth/v1/token?grant_type=refresh_token", "POST", {"refresh_token": session["refresh_token"]})
    check("signed-out session cannot refresh", code == 400)
    # JWTs issued before signout may remain valid until expiry; do not assert immediate JWT revocation.
    check("switching client from A to B returns B identity", a2.login(email_b, password) == owner_b)
    code, rows, _ = a2.read(owner_a)
    check("switched B client cannot read A snapshot", code == 200 and rows == [])


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    WORK.chmod(0o700)
    config = WORK / "supabase" / "config.toml"
    if config.exists():
        raise RuntimeError("Remove the prior disposable .tmp/auth-sync-local directory before rerunning")
    subprocess.run(["supabase", "init", "--workdir", str(WORK)], check=True, capture_output=True)
    contents = config.read_text().replace('project_id = "auth-sync-local"', 'project_id = "' + PROJECT + '"')
    for source, target in [("54321", "56721"), ("54322", "56722"), ("54320", "56720"), ("54323", "56723"), ("54324", "56724"), ("54327", "56727"), ("54329", "56729")]:
        contents = contents.replace(source, target)
    contents = contents.replace('site_url = "http://127.0.0.1:3000"', 'site_url = "' + CALLBACK + '"')
    contents = contents.replace('additional_redirect_urls = ["https://127.0.0.1:3000"]', 'additional_redirect_urls = ["' + CALLBACK + '"]')
    contents = contents.replace("enable_confirmations = false", "enable_confirmations = true")
    contents = contents.replace("email_sent = 2", "email_sent = 100")
    contents += '\n[auth.email.template.magic_link]\nsubject = "Local Recipe email code"\ncontent_path = "./supabase/templates/magic_link.html"\n'
    contents += '\n[auth.email.template.confirmation]\nsubject = "Local Recipe confirmation"\ncontent_path = "./supabase/templates/confirmation.html"\n'
    config.write_text(contents)
    templates = config.parent / "templates"
    templates.mkdir(exist_ok=True)
    (templates / "magic_link.html").write_text('<p>Code: {{ .Token }}</p>')
    (templates / "confirmation.html").write_text('<p>Code: {{ .Token }}</p><a href="{{ .ConfirmationURL }}">Confirm</a>')
    migration_dir = config.parent / "migrations"
    migration_dir.mkdir(exist_ok=True)
    hashes = {}
    for name in MIGRATIONS:
        source = ROOT / "supabase" / "migrations" / name
        shutil.copyfile(source, migration_dir / name)
        hashes[name] = hashlib.sha256(source.read_bytes()).hexdigest()
    try:
        startup = WORK / "startup.log"
        startup.touch(mode=0o600)
        with startup.open("w") as log:
            subprocess.run(["supabase", "start", "--workdir", str(WORK), "-x",
                            "realtime,storage-api,imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"],
                           check=True, stdout=log, stderr=log)
        status = json.loads(subprocess.check_output(["supabase", "status", "--workdir", str(WORK), "-o", "json"], stderr=subprocess.DEVNULL))
        if status["API_URL"] != "http://127.0.0.1:56721" or status["MAILPIT_URL"] != "http://127.0.0.1:56724":
            raise RuntimeError("Unexpected local endpoints")
        images = subprocess.check_output(["docker", "ps", "--filter", "name=" + PROJECT, "--format", "{{.Image}}"], text=True).splitlines()
        run_checks(status)
    finally:
        # Deletes only this newly-created local project's disposable containers/volumes.
        subprocess.run(["supabase", "stop", "--project-id", PROJECT, "--no-backup"], check=True, capture_output=True)
    report = {"time_utc": datetime.now(timezone.utc).isoformat(), "project": PROJECT,
              "git_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "supabase_cli": subprocess.check_output(["supabase", "--version"], text=True).strip(), "images": images,
              "migration_sha256": hashes, "passed": CHECKS,
              "limitations": "HTTP protocol only; no Swift client, Keychain, device, UI, Apple/Google, hosted SMTP, Storage or account deletion acceptance."}
    (WORK / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(CHECKS)} checks. Report: {WORK / 'report.json'}")


if __name__ == "__main__":
    main()
