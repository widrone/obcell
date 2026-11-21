# obcell

This repo turns a small Ubuntu PC with a software-defined radio into a complete
**private 5G/4G network and remote-production Obcell**, and keeps it reproducible: wipe the
box, or buy a new one, run one command, and you get the same Obcell back.

What a finished Obcell gives you:

| You get | What it is |
|---|---|
| A private 4G/5G cell | Open5GS core and an OCUDU gNB driving the SDR (band n40 on the reference Obcell) |
| Remote production | Open Live Studio (vision mixer, guests over WHIP), Open Intercom, and radio-into-intercom |
| A portal | Homepage with status tiles and on-air buttons, all behind one login (Caddy + Authelia) |
| Monitoring | Grafana dashboards, Prometheus alerts, ntopng traffic, an OpenWebRX spectrum view |
| A runbook | the `obcell` command on the box (`obcell status`, `obcell backup`, `obcell onair`, …) |

Everything is built with ordinary open-source tools: Ansible, Docker Compose, systemd, apt
and git. Running it again only fixes whatever drifted, and `--check --diff` shows the drift
without changing anything.

> **Radio safety.** The reference Obcell transmits in licensed spectrum (n40, 2300–2400 MHz).
> The playbook **never** starts the gNB and never enables it at boot; going on air is
> always a manual step (`obcell onair` or the Homepage button). Make sure you are allowed
> to transmit where you are.

## What you need

- **A PC** with 4+ CPU threads (the gNB gets half of them), 8 GB+ RAM, an SSD, and
  Ubuntu Server LTS. The reference Obcell is an Intel NUC with an i5-6260U and
  15 GB of RAM.
- **An SDR** supported by an entry in `group_vars/all/sdr.yml`: LimeSDR Mini or USB, a
  USRP B2xx or X3xx, or `zmq`, which is no hardware at all and is used for tests.
- Optional: an RTL-SDR dongle for the spectrum view, and a Tailscale account for remote access.

### Ubuntu releases

| Release | Status |
|---|---|
| 22.04 LTS (jammy) | **Tested.** The reference Obcell runs it; a full fresh install passes in a test container |
| 24.04 LTS (noble) | **Prepared, not yet tested.** Every package is available ([details](docs/ubuntu-releases.md)) |
| 26.04 LTS (resolute) | **Prepared, not yet tested.** MongoDB is installed from its 24.04 repo ([details](docs/ubuntu-releases.md)) |

## Install an Obcell box

On the new box, with Ubuntu Server installed, log in as the user who will run it and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/widrone/obcell/main/install.sh | bash
```

It installs git, clones this repo to `~/obcell-src`, sets up Ansible, writes a starter config
for the box (the radio is detected from USB) and asks before it starts the build (~1 hour).
Running it again updates the repo and keeps your settings. It never puts the cell on air.
Read [install.sh](install.sh) first if you like; it is short.

### By hand

Clone this repo to `~/obcell-src` (`~/obcell` is where
the playbook puts the `obcell` command and runbook):

```bash
git clone https://github.com/widrone/obcell ~/obcell-src && cd ~/obcell-src
./bootstrap.sh && . ./activate                        # Ansible in a venv (~2 minutes)
mkdir -p inventory/host_vars/<newbox> && cp inventory/host_vars/example/main.yml inventory/host_vars/<newbox>/
$EDITOR inventory/hosts.yml inventory/host_vars/<newbox>/main.yml    # describe the box
ansible-playbook site.yml --limit <newbox> --check --diff            # preview
ansible-playbook site.yml --limit <newbox> -e obcell_confirm_host=<newbox>   # build (~1 h the first time)
ansible-playbook verify.yml --limit <newbox>                         # health check
```

- **`host_vars/<newbox>/main.yml`** holds everything that differs between boxes: user, LAN
  interface, SDR type and serial, cell settings, tailnet name, and optional parts.
  [docs/configuration.md](docs/configuration.md) explains every setting.
- **`obcell_confirm_host`** is only needed while the box's hostname isn't the Obcell name yet.
  The playbook refuses to change a machine that isn't the Obcell it was asked to build.
- **sudo:** the playbook uses sudo for system changes. If your user needs a password for
  sudo (the Ubuntu default), add `-K` to the `site.yml` and `verify.yml` commands and type it
  once per run.
- **Over SSH:** you can also run Ansible from a laptop over SSH instead of on the box itself
  (`ansible_host` and `ansible_user` in `inventory/hosts.yml`).

## Day to day

On the Obcell box, `obcell help` lists everything; `~/obcell/README.md` on the box is the full
runbook (addresses, ports, where files live, what to do when something breaks).

```bash
obcell status          # cell, core, containers, alerts, Tailscale, host — one screen
obcell onair           # start the cell (asks first)    obcell offair   # stop it
obcell backup          # subscribers, productions, configs and the CA -> ~/obcell-backups
```

## Secrets, backups, new hardware

- **Secrets** (passwords, API keys, SIM keys) live in `secrets/<host>/` on the machine that runs
  Ansible. That folder is **never committed** (it's git-ignored). A new box gets fresh
  secrets on its first run.
- **To move an Obcell to new hardware with the same passwords,** copy its secrets folder across
  yourself (for example with `scp -r`), never through GitHub. Then restore the data:

  ```bash
  ansible-playbook restore.yml --limit <host> -e backup=~/obcell-backups/obcell-config-YYYYMMDD-HHMM.tar.gz
  ```

  This brings back the SIM subscribers, the Open Live productions and the Caddy root CA,
  so phones and laptops keep trusting the Obcell.

## Testing changes

Changes are tested in throw-away LXD containers on a separate **test machine**, never on a
Obcell box. One command installs the whole Obcell on each Ubuntu release, checks it twice, and
brings up a virtual cell with a virtual phone:

```bash
tests/lxd/setup-host.sh        # once, on the test machine
tests/matrix.sh                # 22.04, 24.04 and 26.04; results in tests/.work/results/latest/summary.md
```

The quick checks (lint, syntax, unit tests, shellcheck) also run on GitHub for every push.
See [docs/testing.md](docs/testing.md).

## Working with an AI agent

`CLAUDE.md` holds the rules an agent must follow in this repo: radio safety, secrets, which
machines it may change. Open work is written up as task files in
[`docs/tasks/`](docs/tasks/), so a person or an agent can pick one up, do it, and record
what they found.

## Repo layout

```
site.yml              builds an Obcell (all roles, in order)
verify.yml            read-only health check
restore.yml           puts data back from an `obcell backup` archive
inventory/            your Obcells (git-ignored, written by install.sh) + host_vars/example
group_vars/all/       defaults for every Obcell: main.yml, SDR profiles, web names, secrets
roles/                one role per part: base, docker, tailscale, open5gs, sdr, ocudu, srsue,
                      obcell_cli, openlive, intercom, monitoring, cell_control (+ common helpers)
filter_plugins/       small Jinja helpers (CPU lists, URLs)
tests/                test matrix, LXD harness, unit tests
docs/                 configuration, testing, Ubuntu releases, tasks
```

## Licence

[MIT](LICENSE). The upstream projects the playbook installs (Open5GS, OCUDU, srsRAN, Open Live,
Open Intercom and the rest) keep their own licences; the patches in `roles/*/files/` apply to
them under those licences. IBM Plex Mono is under the SIL Open Font License (included).
