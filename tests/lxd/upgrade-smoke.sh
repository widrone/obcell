#!/usr/bin/env bash
# MongoDB / Node.js upgrade test in an LXD test container (task 009, docs/upgrades.md).
# Starts from a box on the old versions (MongoDB 6.0, Node 20: `reset-old`), seeds extra
# subscribers, upgrades, and compares a fingerprint of the Open5GS database before and after.
# Ansible runs inside the container, like on a real box.
#
#   tests/lxd/upgrade-smoke.sh [RELEASE] seed            add 5 throw-away subscribers, save the reference dump
#   tests/lxd/upgrade-smoke.sh [RELEASE] state           versions, FCV, data fingerprint, WebUI login
#   tests/lxd/upgrade-smoke.sh [RELEASE] route-a NODE    upgrade.yml in place, then site.yml + verify.yml
#   tests/lxd/upgrade-smoke.sh [RELEASE] route-b NODE    backup, wipe, fresh MongoDB, mongorestore --drop, site.yml + verify.yml
#   tests/lxd/upgrade-smoke.sh [RELEASE] reset-old       back to MongoDB 6.0 + Node 20 with the reference data
#   tests/lxd/upgrade-smoke.sh [RELEASE] webui NODE      only move Node.js (rebuilds the WebUI), then state
# RELEASE defaults to 22.04 (the only release that has MongoDB 6.0/7.0 packages).
# Every phase prints "TIME <phase> <seconds>"; `state` prints "STATE ..." lines to compare.
set -euo pipefail
cd "$(dirname "$0")/../.."
. tests/lxd/lib.sh
REL=22.04
case "${1:-}" in 2[0-9].04) REL=$1; shift ;; esac
C=$(container_for "$REL")
CMD=${1:-state}; NODE=${2:-}
TARGET=${OBCELL_TEST_MONGODB:-8.0}
W=/home/ubuntu/upgrade-test                       # reference dump + logs, inside the container

[ "$(lxc list "^$C\$" --format csv -c s 2>/dev/null)" = RUNNING ] || die "container $C is not running"
lxc exec "$C" -- systemd-detect-virt -c -q || die "$C does not look like a container; refusing"

cx() { lxc exec "$C" -- bash -c "$1"; }                          # as root
ux() { lxc exec "$C" -- sudo -iu ubuntu bash -c "$1"; }          # as the Obcell user
# Copy this checkout in (tracked + new files, never secrets/) and run a playbook there.
play() {
  ux "mkdir -p ~/obcell-src $W"
  git ls-files -co --exclude-standard -z | tar c --null -T - \
    | lxc exec "$C" -- sudo -u ubuntu tar x -C /home/ubuntu/obcell-src
  ux "cd ~/obcell-src && . ./activate && ansible-playbook -i tests/lxd/inventory-local.yml --limit $C -e srsue_enabled=true $(printf ' %q' "$@")"
}
timed() { local p=$1 t0; shift; t0=$(date +%s); "$@"; echo "TIME $p $(( $(date +%s) - t0 ))"; }

# sha256 over the documents of every collection in the open5gs database, in _id order.
fingerprint() {
  cx "HOME=/root mongosh --quiet open5gs --eval '
    const out = [];
    for (const c of db.getCollectionNames().filter(n => n !== \"sessions\").sort()) {
      out.push(c + \"=\" + db[c].countDocuments());
      out.push(EJSON.stringify(db[c].find().sort({_id: 1}).toArray(), {relaxed: false}));
    }
    print(out.filter((_, i) => i % 2 == 0).join(\" \") + \" sha256=\" +
          require(\"crypto\").createHash(\"sha256\").update(out.join(\"\\n\")).digest(\"hex\").slice(0, 16));'"
}

# Log in to the WebUI like a browser (CSRF token, session cookie), then list the
# subscribers through its own API (mongoose -> MongoDB).
webui_login() {
  cx 'set -e; j=$(mktemp); u=http://127.0.0.1:9999
    for _ in $(seq 30); do curl -sf -o /dev/null $u/api/auth/csrf && break; sleep 2; done
    t=$(curl -s -c $j -b $j $u/api/auth/csrf | python3 -c "import json,sys; print(json.load(sys.stdin)[\"csrfToken\"])")
    code=$(curl -s -o /dev/null -w "%{http_code}" -c $j -b $j -H "X-CSRF-Token: $t" -H "Content-Type: application/json" \
           --data "{\"username\":\"admin\",\"password\":\"1423\"}" $u/api/auth/login)
    jwt=$(curl -s -c $j -b $j $u/api/auth/session | python3 -c "import json,sys; print(json.load(sys.stdin).get(\"authToken\", \"\"))")
    n=$(curl -s -H "Authorization: Bearer $jwt" $u/api/db/Subscriber | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo none)
    rm -f $j
    if [ "$code" = 302 ] && [ -n "$jwt" ] && [ "$n" != none ]; then echo "login=PASS api_subscribers=$n"; else echo "login=FAIL http=$code api_subscribers=$n"; fi'
}

state() {
  echo "STATE versions $(cx "dpkg-query -W -f='\${Package}=\${Version} ' mongodb-org-server nodejs; echo; cat /usr/lib/node_modules/open5gs/.obcell-build 2>/dev/null")"
  echo "STATE fcv $(cx "HOME=/root mongosh --quiet --eval 'db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1}).featureCompatibilityVersion.version'")"
  echo "STATE repos $(cx 'ls /etc/apt/sources.list.d/ | grep -E "mongodb|nodesource" | tr "\n" " "')"
  echo "STATE data $(fingerprint)"
  echo "STATE webui $(webui_login)"
  echo "STATE units $(cx 'systemctl is-active mongod open5gs-udrd open5gs-pcfd open5gs-hssd open5gs-pcrfd open5gs-webui | sort | uniq -c | tr -s " \n" " "')"
}

# Wipe MongoDB (packages, data, repos) so the open5gs role installs a fresh series.
wipe_mongodb() {
  cx 'systemctl stop mongod; DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "mongodb-org*" >/dev/null
      rm -rf /var/lib/mongodb /var/log/mongodb /etc/apt/sources.list.d/mongodb-org-*.list /usr/share/keyrings/mongodb-server-*.gpg'
}
restore_dump() {   # $1 = archive inside the container; replaces the open5gs database
  cx "mongorestore --quiet --drop --gzip --archive=$1 --nsInclude='open5gs.*'
      systemctl restart open5gs-udrd open5gs-pcfd open5gs-hssd open5gs-pcrfd open5gs-webui"
}

case $CMD in
  seed)
    # 5 more subscribers cloned from the test SIM, each with its own random keys.
    cx "HOME=/root mongosh --quiet open5gs --eval '
      const crypto = require(\"crypto\");
      const t = db.subscribers.findOne({imsi: \"999700000000099\"});
      for (let i = 1; i <= 5; i++) {
        const s = Object.assign({}, t); delete s._id;
        s.imsi = \"99970000000010\" + i;
        s.security = Object.assign({}, t.security, {k: crypto.randomBytes(16).toString(\"hex\").toUpperCase(),
                                                    opc: crypto.randomBytes(16).toString(\"hex\").toUpperCase()});
        db.subscribers.updateOne({imsi: s.imsi}, {\$setOnInsert: s}, {upsert: true});
      }
      print(\"subscribers=\" + db.subscribers.countDocuments());'"
    ux "mkdir -p $W && mongodump --quiet --db open5gs --gzip --archive=$W/reference.archive.gz && ls -l $W/reference.archive.gz"
    state ;;
  state) state ;;
  route-a)
    [ -n "$NODE" ] || die "route-a needs the Node.js major, e.g. 24"
    timed upgrade play upgrade.yml -e mongodb_version="$TARGET"
    timed site play site.yml -e mongodb_version="$TARGET" -e nodejs_major="$NODE"
    timed verify play verify.yml -e mongodb_version="$TARGET" -e nodejs_major="$NODE"
    state ;;
  route-b)
    [ -n "$NODE" ] || die "route-b needs the Node.js major, e.g. 24"
    t0=$(date +%s)
    ux "~/obcell/obcell backup | tail -2"
    a=$(ux 'ls -1t ~/obcell-backups/obcell-config-*.tar.gz | head -1')
    ux "cd $W && tar -xzf $a ./open5gs-mongo.archive.gz && mv open5gs-mongo.archive.gz route-b.archive.gz"
    wipe_mongodb
    play site.yml --tags open5gs -e mongodb_version="$TARGET" -e nodejs_major="$NODE"
    restore_dump "$W/route-b.archive.gz"
    echo "TIME route-b-core $(( $(date +%s) - t0 ))"
    timed site play site.yml -e mongodb_version="$TARGET" -e nodejs_major="$NODE"
    timed verify play verify.yml -e mongodb_version="$TARGET" -e nodejs_major="$NODE"
    state ;;
  reset-old)
    t0=$(date +%s)
    wipe_mongodb
    play site.yml --tags open5gs -e mongodb_version=6.0 -e nodejs_major=20
    restore_dump "$W/reference.archive.gz"
    echo "TIME reset-old $(( $(date +%s) - t0 ))"
    state ;;
  webui)
    [ -n "$NODE" ] || die "webui needs the Node.js major, e.g. 26"
    timed webui play site.yml --tags open5gs -e nodejs_major="$NODE"
    state ;;
  *) die "unknown command '$CMD' (seed|state|route-a NODE|route-b NODE|reset-old|webui NODE)" ;;
esac
