# Upgrading MongoDB and Node.js on an existing Obcell

New Obcells install MongoDB 8.0 and Node.js 26 on every Ubuntu release. Obcells built
before 2026-11 on Ubuntu 22.04 run MongoDB 6.0 and Node.js 20, both past end of life. This page
moves such a box to the current versions without losing the subscribers (the SIM keys).

| Component | Old | New | End of life of the new one |
|---|---|---|---|
| MongoDB (the Open5GS subscriber database) | 6.0 (EOL 2025-07-31) | 8.0 | 2029-10-31 |
| Node.js (runs the Open5GS WebUI) | 20 (EOL 2026-04-30), 24 | 26 | 2029-04-30 |

The WebUI (Open5GS v2.8.0) runs on Node.js 26 only with one dependency moved: its lockfile has
`jwa` 1.4.1, which loads `buffer-equal-constant-time`, which reads `SlowBuffer`, which Node.js 25
removed, so the WebUI crashes at start. `jwa` 1.4.2 is in the range the WebUI's `jws` asks for
and uses `crypto.timingSafeEqual` instead. The build applies it as an npm override,
`open5gs_webui_npm_overrides: {jwa: "1.4.2"}` in `group_vars/all/main.yml`. Remove it when an
Open5GS release locks `jwa` 1.4.2 or newer. Node.js 24 also runs the build without the pin
([task 014](tasks/014-webui-node26.md)).

## What site.yml does, and what it leaves to upgrade.yml

- **Node.js has no data**, so `site.yml` moves a box to `nodejs_major` by itself. It switches
  the NodeSource repository, installs that major, and rebuilds the WebUI. The rebuild keeps
  the WebUI's `.env` (its session secrets), so nobody gets logged out. A stamp file,
  `/usr/lib/node_modules/open5gs/.obcell-build`, records the Open5GS and Node.js versions and
  the npm overrides the WebUI was built with (`open5gs 2.8.0 node 26 jwa@1.4.2`). A box moves
  up from Node.js 24 the same way, with `site.yml` alone. If the WebUI doesn't answer after its
  restart, `site.yml` fails.
- **MongoDB holds the data**, and a newer server can't start on files from two majors back.
  So `site.yml` keeps whatever series a box already runs, and prints
  `MongoDB 6.0 is installed and the playbook wants 8.0 ... run upgrade.yml`. Only
  `upgrade.yml` changes the series. MongoDB supports one major at a time, so it goes
  6.0 → 7.0 → 8.0, raising the *feature compatibility version* (FCV) after each step.
  The data stays in place.

## Procedure

Run these on the control machine (on the box itself, for a box that manages itself). Pick a time
when nobody needs the cell or the WebUI; the core loses its database for a few seconds per step.

1. **Take the cell off air** if it is on: `obcell offair`. `upgrade.yml` refuses to run
   while the gNB unit is active.
2. **Preview:**

   ```bash
   ansible-playbook upgrade.yml --limit <host> --check
   ```

   The `Plan` line shows the steps, e.g. `MongoDB 6.0 -> 7.0 -> 8.0`. Nothing is changed.
3. **Upgrade MongoDB** (about a minute on the test machine):

   ```bash
   ansible-playbook upgrade.yml --limit <host>
   ```

   It runs `obcell backup` first (the archive lands in `~/obcell-backups/`; the run stops if
   mongodump fails), then for each step: checks the FCV, swaps the MongoDB repository, installs
   that series' packages, restarts mongod, waits for it, raises the FCV. At the end it restarts
   the services that talk to MongoDB (UDR, PCF, HSS, PCRF, WebUI).
4. **Move Node.js and rebuild the WebUI** (about 3 minutes). Look first, then apply:

   ```bash
   ansible-playbook site.yml --limit <host> --check --diff
   ansible-playbook site.yml --limit <host>
   ```

   Expected in the dry run: the NodeSource repository (e.g. `node_20.x` → `node_26.x`),
   `Node.js 26 would come from the new repository`, `WebUI would be rebuilt`, and the
   build stamp. Nothing else should change. On Ubuntu, apt's `needrestart` restarts the old
   WebUI as soon as the new Node.js is in; a build without the `jwa` pin then crash-loops for
   the minute until the rebuild replaces it. That is expected.
5. **Check:**

   ```bash
   ansible-playbook verify.yml --limit <host>
   ```

   Also log in to the WebUI (`https://<host>:9443`) and look at a subscriber.

## If something goes wrong

- **upgrade.yml stopped partway, mongod runs** (`systemctl status mongod`): run it again.
  It starts from the series that is installed now, and first sets the FCV to that series if
  the previous run didn't get that far. Upgrading in two runs (6.0 → 7.0, then 7.0 → 8.0) was
  tested.
- **mongod doesn't start, or anything else looks wrong: restore from the backup** that
  `upgrade.yml` took (`journalctl -u mongod` says why it didn't start). This route was also
  tested (see [task 009](tasks/009-eol-upgrades.md)):

  ```bash
  # on the box
  sudo systemctl stop mongod
  sudo apt-get purge -y 'mongodb-org*'
  sudo rm -rf /var/lib/mongodb /etc/apt/sources.list.d/mongodb-org-*.list /usr/share/keyrings/mongodb-server-*.gpg
  # control machine: installs a fresh mongodb_version (no data yet)
  ansible-playbook site.yml --limit <host> --tags open5gs
  # on the box: put the open5gs database back exactly as it was in the backup
  tar -xzf ~/obcell-backups/obcell-config-<time>.tar.gz ./open5gs-mongo.archive.gz
  mongorestore --drop --gzip --archive=open5gs-mongo.archive.gz --nsInclude='open5gs.*'
  sudo systemctl restart open5gs-udrd open5gs-pcfd open5gs-hssd open5gs-pcrfd open5gs-webui
  ```

  Use `mongorestore --drop` here, not `restore.yml`. `restore.yml` keeps documents that are
  already there, and a fresh install has already added the SIMs from
  `secrets/<host>/subscribers.yml` and, if the WebUI was rebuilt, the default `admin`/`1423`
  account. Those would win over the backup's versions: SIMs edited in the WebUI would go back to
  their secrets-file values, and a changed admin password would go back to the default.

## Testing it

`tests/lxd/upgrade-smoke.sh` runs the routes in a 22.04 test container and compares a
fingerprint of the whole `open5gs` database and a WebUI login before and after. See
[testing.md](testing.md#upgrade-test).
