#!/usr/bin/env bash
# Read-only audit of Gitea identities, tokens, keys, and registration.
set -euo pipefail

DB="${GITEA_DB:-/srv/gitea/data/gitea/gitea.db}"
APP_INI="${GITEA_APP_INI:-/srv/gitea/data/gitea/conf/app.ini}"

[[ -r "$DB" ]] || { echo "error: cannot read $DB (run as root)" >&2; exit 2; }
[[ -r "$APP_INI" ]] || { echo "error: cannot read $APP_INI" >&2; exit 2; }

python3 - "$DB" "$APP_INI" <<'PY'
import os
import re
import sqlite3
import sys
import time

db_path, app_ini = sys.argv[1], sys.argv[2]
now = int(time.time())
critical = []
warnings = []


def line(text=""):
    print(text)


def days(ts):
    return max(0, (now - int(ts or 0)) // 86400)


def fail(msg):
    critical.append(msg)


def warn(msg):
    warnings.append(msg)


db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
db.row_factory = sqlite3.Row

users = db.execute(
    "select id, lower_name, type, is_admin, is_active, prohibit_login, created_unix "
    "from user order by id"
).fetchall()
individuals = [u for u in users if u["type"] == 0]
admins = [u for u in users if u["is_admin"]]

line("== identities ==")
for u in users:
    kind = "organization" if u["type"] == 1 else "individual"
    flags = []
    if u["is_admin"]:
        flags.append("admin")
    if not u["is_active"]:
        flags.append("inactive")
    if u["prohibit_login"]:
        flags.append("login-prohibited")
    suffix = f" ({', '.join(flags)})" if flags else ""
    line(f"  {u['lower_name']}: {kind}{suffix}")

if len(admins) != 1:
    fail(f"expected exactly one admin, found {len(admins)}")
for u in admins:
    if u["lower_name"] != "human":
        fail(f"unexpected admin: {u['lower_name']}")
for u in users:
    if u["lower_name"].startswith("bot-") and u["is_admin"]:
        fail("bot accounts must not be administrators")
    if u["type"] == 1 and u["is_admin"]:
        fail(f"organization account {u['lower_name']} must not be an administrator")

line()
line("== two-factor authentication ==")
two_factor = {r[0] for r in db.execute("select uid from two_factor")}
for u in individuals:
    status = "enabled" if u["id"] in two_factor else "missing"
    line(f"  {u['lower_name']}: {status}")
if not individuals:
    fail("no individual accounts found")
for u in individuals:
    if u["id"] not in two_factor:
        warn(f"two-factor authentication is not enabled for {u['lower_name']}")

line()
line("== access tokens ==")
tokens = db.execute(
    "select id, uid, name, scope, created_unix from access_token order by id"
).fetchall()
if not tokens:
    warn("no access tokens")
for t in tokens:
    owner = next((u["lower_name"] for u in users if u["id"] == t["uid"]), f"uid:{t['uid']}")
    age = days(t["created_unix"])
    line(f"  {owner}/{t['name']}: {t['scope']} ({age}d old)")
    if t["scope"] == "all":
        fail(f"token {owner}/{t['name']} has the all scope")
    if age > 180:
        warn(f"token {owner}/{t['name']} is {age} days old")

line()
line("== keys ==")
ssh_keys = db.execute("select id, owner_id, name, created_unix from public_key order by id").fetchall()
deploy_keys = db.execute("select id, name, repo_id, created_unix from deploy_key order by id").fetchall()
for k in ssh_keys:
    owner = next((u["lower_name"] for u in users if u["id"] == k["owner_id"]), f"uid:{k['owner_id']}")
    line(f"  ssh {owner}/{k['name']} ({days(k['created_unix'])}d old)")
for k in deploy_keys:
    line(f"  deploy repo:{k['repo_id']}/{k['name']} ({days(k['created_unix'])}d old)")
    warn(f"deploy key present: repo:{k['repo_id']}/{k['name']}")

line()
line("== webhooks ==")
webhooks = db.execute("select id, name, url, is_active from webhook order by id").fetchall()
if not webhooks:
    line("  none")
for w in webhooks:
    state = "active" if w["is_active"] else "inactive"
    line(f"  {w['name']}: {w['url']} ({state})")
    if w["is_active"]:
        warn(f"active webhook: {w['name']}")

line()
line("== registration ==")
text = open(app_ini, encoding="utf-8", errors="replace").read()
match = re.search(r"^DISABLE_REGISTRATION\s*=\s*(\w+)", text, re.M)
value = match.group(1).lower() if match else "false"
line(f"  disabled: {value}")
if value != "true":
    fail("public registration is enabled")

line()
line("== result ==")
for msg in warnings:
    line(f"  warning: {msg}")
for msg in critical:
    line(f"  critical: {msg}")
if critical:
    sys.exit(1)
print("access audit: ok")
PY
