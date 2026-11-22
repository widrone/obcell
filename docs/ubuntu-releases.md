# Ubuntu releases

## Status

| Release | Python | ansible-core | Status |
|---|---|---|---|
| 22.04 LTS jammy | 3.10 | 2.17 | **Tested**: the reference Obcell runs it; LXD fresh install, idempotent re-run, verify and gNB NG Setup all pass (2026-11-20) |
| 24.04 LTS noble | 3.12 | 2.20 | **Tested in containers**: LXD fresh install, idempotent re-run, verify, gNB NG Setup and UE end to end all pass (2026-11-22, bd3c1f5; [task 003](tasks/003-ubuntu-2404.md)) |
| 26.04 LTS resolute | 3.14 | 2.20 | **Tested in containers**: the same, with MongoDB from its noble repo (2026-11-22, bd3c1f5; [task 004](tasks/004-ubuntu-2604.md)) |

"In containers": ZeroMQ virtual radio only. No real Obcell runs 24.04 or 26.04 yet, so the SDR
drivers there (LimeSuite and UHD from the Ubuntu archive) are untested with hardware. 22.04 was
re-checked from scratch at the same commit.

The list the playbook accepts is `obcell_supported_releases` in `group_vars/all/main.yml`.

## What was checked (2026-11-21)

### Third-party apt repos

| Repo | jammy | noble | resolute | Notes |
|---|---|---|---|---|
| Open5GS PPA (`open5gs/latest`) | 2.8.0 | 2.8.0 | 2.8.0 | |
| MongoDB server | 6.0 / 7.0 / 8.0 | 8.0, 8.2 | **none yet** (only client tools) | resolute uses the noble 8.0 repo: 8.0.38 installs and runs there (needs AVX on x86) |
| NodeSource Node 20 | ✓ | ✓ | ✓ | one repo for all releases |
| Tailscale | ✓ | ✓ | ✓ | |
| MyriadRF PPA (LimeSuite) | ✓ | – | – | not needed on 24.04+: the Ubuntu archive has LimeSuite 23.11 |
| Ettus PPA (UHD) | ✓ | ✓ | ✓ | not used; the Ubuntu archive is enough |

### Ubuntu archive packages

All packages the roles install exist on noble and resolute. The ones that matter for the
builds have moved a lot:

| Package | jammy | noble | resolute | What happened (2026-11-22) |
|---|---|---|---|---|
| gcc / g++ | 11 | 13 | 15 | OCUDU built unchanged. srsRAN_4G (srsUE) needed two upstream fixes as patches and `-Wno-error=array-bounds` on 13, and one more patch on 15 (`roles/srsue/files/`) |
| cmake | 3.22 | 3.28 | **4.2** | configures OCUDU and srsRAN_4G with deprecation warnings only |
| libmbedtls-dev | 2.28 | 2.28 | **3.6** | srsUE builds and attaches against 3.6 unchanged |
| libboost-program-options-dev | 1.74 | 1.83 | 1.90 | |
| libuhd-dev | 4.1 | 4.6 | 4.9 | |
| limesuite / soapysdr-module-lms7 | 23.11 (PPA) | 23.11 | 23.11 | |
| docker.io / compose v2 / buildx | 29.1 / 2.40 / 0.30 | same | same | |
| python3 | 3.10 | 3.12 | 3.14 | the controller needs ansible-core 2.20 on 3.12+ |

### Controller (Ansible)

ansible-core supports only a few controller Pythons per release. `requirements.txt` picks
the version from the Python it is installed with: 2.17 on Python 3.10 (22.04), 2.19 on 3.11,
and 2.20 on 3.12+ (24.04, 26.04). The playbook runs unchanged under 2.20 (the 24.04 and 26.04
tests bootstrap their own controller). An older controller works too: ansible-core 2.17 drove
a 26.04 box from outside (install, verify and an idempotent re-run, no warnings), so a 22.04
machine can manage a 26.04 Obcell. `passlib` (used to make the password hashes) is unmaintained
but still works on Python 3.14.

Moving which machine runs Ansible for an Obcell means moving `secrets/<host>/` with it: a
controller without them generates new ones, and Authelia then refuses to start because its
database is encrypted with the old key.

### Release differences the roles handle

- **No `apt-key` on 26.04** (apt 3): `apt_repository` can't fetch a PPA's key there, so
  `roles/common/tasks/ppa.yml` uses `add-apt-repository` when `apt-key` is missing.
- **Ubuntu's `nodejs` outranks NodeSource's on 26.04** (22.x vs 20.x) and has no npm:
  `/etc/apt/preferences.d/nodesource` pins NodeSource's.

## Known gaps to watch

- MongoDB 6.0 (what 22.04 Obcells run) has been end of life since mid-2025. Moving an Obcell to
  8.0 means going through 7.0 ([task 009](tasks/009-eol-upgrades.md)).
- Node 20 has been end of life since April 2026; it is only used to build the WebUI.
- The `obcell slides` renderer uses the `playwright/python:…-jammy` image. That is a container,
  so it doesn't depend on the host release.

## Adding a new Ubuntu release

1. Add its codename to `obcell_supported_releases` (`group_vars/all/main.yml`).
2. Add it to `OBCELL_TEST_RELEASES` and `container_for` in `tests/lxd/lib.sh`, and as a host in
   `tests/lxd/inventory.yml` and `tests/lxd/inventory-local.yml`.
3. Check the third-party repos above for the codename. If MongoDB doesn't publish it yet,
   leave `mongodb_repo_release` on the newest release it does publish.
4. Run `tests/matrix.sh <version>` on the test machine and fix what fails.
5. Update the tables in this file and in the README.
