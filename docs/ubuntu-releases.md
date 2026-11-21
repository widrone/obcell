# Ubuntu releases

## Status

| Release | Python | ansible-core | Status |
|---|---|---|---|
| 22.04 LTS jammy | 3.10 | 2.17 | **Tested**: the reference Obcell runs it; LXD fresh install, idempotent re-run, verify and gNB NG Setup all pass (2026-11-20) |
| 24.04 LTS noble | 3.12 | 2.20 | **Prepared**: every package and repo is available; full install not run yet ([task 003](tasks/003-ubuntu-2404.md)) |
| 26.04 LTS resolute | 3.14 | 2.20 | **Prepared**: available except MongoDB, which uses its noble build; full install not run yet ([task 004](tasks/004-ubuntu-2604.md)) |

The list the playbook accepts is `obcell_supported_releases` in `group_vars/all/main.yml`.

## What was checked (2026-11-21)

### Third-party apt repos

| Repo | jammy | noble | resolute | Notes |
|---|---|---|---|---|
| Open5GS PPA (`open5gs/latest`) | 2.8.0 | 2.8.0 | 2.8.0 | |
| MongoDB server | 6.0 / 7.0 / 8.0 | 8.0, 8.2 | **none yet** (only client tools) | resolute uses the noble 8.0 repo: a dry-run install resolves every dependency |
| NodeSource Node 20 | ✓ | ✓ | ✓ | one repo for all releases |
| Tailscale | ✓ | ✓ | ✓ | |
| MyriadRF PPA (LimeSuite) | ✓ | – | – | not needed on 24.04+: the Ubuntu archive has LimeSuite 23.11 |
| Ettus PPA (UHD) | ✓ | ✓ | ✓ | not used; the Ubuntu archive is enough |

### Ubuntu archive packages

All packages the roles install exist on noble and resolute. The ones that matter for the
builds have moved a lot:

| Package | jammy | noble | resolute | Risk |
|---|---|---|---|---|
| gcc / g++ | 11 | 13 | 15 | new warnings and stricter headers in the pinned OCUDU / srsRAN_4G sources |
| cmake | 3.22 | 3.28 | **4.2** | CMake 4 rejects `cmake_minimum_required` below 3.5 (fix: `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`) |
| libmbedtls-dev | 2.28 | 2.28 | **3.6** | mbedTLS 3 changed its API; srsRAN_4G 23.11 may not build |
| libboost-program-options-dev | 1.74 | 1.83 | 1.90 | |
| libuhd-dev | 4.1 | 4.6 | 4.9 | |
| limesuite / soapysdr-module-lms7 | 23.11 (PPA) | 23.11 | 23.11 | |
| docker.io / compose v2 / buildx | 29.1 / 2.40 / 0.30 | same | same | |
| python3 | 3.10 | 3.12 | 3.14 | the controller needs ansible-core 2.20 on 3.12+ |

### Controller (Ansible)

ansible-core supports only a few controller Pythons per release. `requirements.txt` picks
the version from the Python it is installed with: 2.17 on Python 3.10 (22.04), 2.19 on 3.11,
and 2.20 on 3.12+ (24.04, 26.04). ansible-core 2.19 changed templating (stricter
conditionals, lazy templating), so the playbook has not yet run under 2.20; CI and tasks
003/004 cover it. `passlib` (used to make the password hashes) is unmaintained; check that
it still works on Python 3.14.

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
