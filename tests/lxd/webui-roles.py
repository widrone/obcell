"""Account-role checks against the Open5GS WebUI in a test container (task 015).

Runs inside the container (`upgrade-smoke.sh … roles` pipes it to python3). It adds a
throw-away `user`-role account straight into MongoDB, logs in as it like a browser, tries
what an operator without the admin role must not be able to do, checks that the allowed
things still work, and removes every account it made. Prints RESULT lines; the expected
value after task 015 is in brackets.

Argument: the admin password of the test container's WebUI (the default one, 1423).
"""
import hashlib
import http.cookiejar
import json
import os
import re
import secrets
import subprocess
import sys
import urllib.error
import urllib.request

WEBUI = "http://127.0.0.1:9999"
PREFIX = "smoke-"   # every account this script makes starts with it
HEX_HASH = re.compile(r"[0-9a-f]{1024}")   # a passport-local-mongoose hash (512 bytes)


def mongo(js):
    out = subprocess.run(["mongosh", "--quiet", "open5gs", "--eval", js], check=True,
                         capture_output=True, text=True, env={**os.environ, "HOME": "/root"})
    return out.stdout.strip()


def salt_and_hash(password):
    """What the WebUI's account form does in the browser (passport-local-mongoose defaults)."""
    salt = secrets.token_hex(32)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 25000, 512)
    return salt, digest.hex()


def add_account(name, role):
    password = secrets.token_hex(12)
    salt, digest = salt_and_hash(password)
    mongo(f"db.accounts.deleteOne({{username: '{name}'}});"
          f"db.accounts.insertOne({{username: '{name}', salt: '{salt}', hash: '{digest}',"
          f" roles: ['{role}'], __v: 0}})")
    return password


def stored(name):
    doc = mongo(f"JSON.stringify(db.accounts.findOne({{username: '{name}'}}, {{roles: 1, hash: 1}}))")
    return json.loads(doc) if doc and doc != "null" else None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Browser:
    def __init__(self):
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()), NoRedirect())
        self.jwt = None

    def call(self, method, path, body=None):
        """(status, text). Non-GET requests carry a fresh CSRF token, like the WebUI's client."""
        headers = {"Content-Type": "application/json"}
        if method != "GET":
            headers["X-CSRF-Token"] = self.csrf()
        if self.jwt:
            headers["Authorization"] = "Bearer " + self.jwt
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(WEBUI + path, data=data, headers=headers, method=method)
        try:
            with self.opener.open(req, timeout=20) as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode(errors="replace")

    def csrf(self):
        with self.opener.open(WEBUI + "/api/auth/csrf", timeout=20) as r:
            return json.load(r)["csrfToken"]

    def login(self, username, password):
        status, _ = self.call("POST", "/api/auth/login", {"username": username, "password": password})
        _, text = self.call("GET", "/api/auth/session")
        self.jwt = json.loads(text).get("authToken") if text.startswith("{") else None
        return status == 302 and bool(self.jwt)


def result(name, value, expected):
    print(f"RESULT {name}={value} [{expected}]")
    return value == expected


def main():
    admin_password = sys.argv[1]
    ok = True
    user = PREFIX + "user"
    try:
        b = Browser()
        if not b.login(user, add_account(user, "user")):
            print("RESULT user_login=FAIL [PASS]")
            return 1
        ok &= result("user_login", "PASS", "PASS")

        # 78cb3cb0: a user-role token must not create an admin account ...
        salt, digest = salt_and_hash(secrets.token_hex(12))
        status, _ = b.call("POST", "/api/db/Account",
                           {"username": PREFIX + "evil", "roles": ["admin"], "salt": salt, "hash": digest})
        made = stored(PREFIX + "evil") is not None
        ok &= result("user_creates_admin", f"ALLOWED({status})" if made else f"REFUSED({status})", "REFUSED(403)")

        # ... nor read password hashes through query options ...
        leaked = []
        for query in ("distinct=hash", "select=%2Bhash", "select=hash"):
            _, text = b.call("GET", "/api/db/Account?" + query)
            if HEX_HASH.search(text):
                leaked.append(query.split("=")[0])
        ok &= result("user_reads_hashes", "YES(" + ",".join(leaked) + ")" if leaked else "NO", "NO")

        # ... nor give itself the admin role ...
        status, _ = b.call("PATCH", f"/api/db/Account/{user}", {"roles": ["admin"]})
        escalated = "admin" in (stored(user) or {}).get("roles", [])
        ok &= result("user_makes_self_admin", f"YES({status})" if escalated else f"NO({status})", "NO(200)")

        # ... but may still change its own password.
        before = (stored(user) or {}).get("hash")
        salt, digest = salt_and_hash(secrets.token_hex(12))
        status, _ = b.call("PATCH", f"/api/db/Account/{user}", {"salt": salt, "hash": digest})
        changed = (stored(user) or {}).get("hash") not in (None, before)
        ok &= result("user_changes_own_password", f"PASS({status})" if changed else f"FAIL({status})", "PASS(200)")

        # fe001033: a token whose account is gone must lose its access.
        mongo(f"db.accounts.deleteOne({{username: '{user}'}})")
        status, _ = b.call("GET", "/api/db/Account")
        ok &= result("deleted_account_token", "REFUSED(401)" if status == 401 else f"ALLOWED({status})", "REFUSED(401)")

        # The admin can still do everything.
        a = Browser()
        if not a.login("admin", admin_password):
            print("RESULT admin_login=FAIL [PASS]")
            return 1
        made_by_admin = PREFIX + "made-by-admin"
        salt, digest = salt_and_hash(secrets.token_hex(12))
        created, _ = a.call("POST", "/api/db/Account",
                            {"username": made_by_admin, "roles": ["user"], "salt": salt, "hash": digest})
        listed, text = a.call("GET", "/api/db/Account")
        deleted, _ = a.call("DELETE", f"/api/db/Account/{made_by_admin}")
        admin_ok = (created, listed, deleted) == (201, 200, 204) and made_by_admin in text
        ok &= result("admin_create_list_delete",
                     "PASS" if admin_ok else f"FAIL({created},{listed},{deleted})", "PASS")
    finally:
        mongo(f"db.accounts.deleteMany({{username: /^{PREFIX}/}})")
    left = mongo(f"db.accounts.countDocuments({{username: /^{PREFIX}/}})")
    print(f"RESULT cleanup={'PASS' if left == '0' else 'FAIL'} [PASS]")
    return 0 if ok and left == "0" else 1


if __name__ == "__main__":
    sys.exit(main())
