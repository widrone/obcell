# CLAUDE.md

Ansible that builds a private 5G/4G cell plus a remote-production and monitoring Obcell on an
Ubuntu box with an SDR. Humans start at `README.md`; the reference docs are in `docs/`. This
file holds the rules and working notes for agents.

## Hard rules

1. **Radio.** The reference Obcell transmits in licensed spectrum (band n40).
   - Never start, restart or enable a gNB on any machine with a real SDR.
   - Never run `obcell onair` or `obcell boot-onair on`, and never set `gnb_start_at_boot: true`.
   - The only gNBs you may start are inside LXD test containers with the ZeroMQ radio,
     through `tests/lxd/radio-smoke.sh`, which checks that for you.
2. **Real Obcells are read-only for you.** That means the reference Obcell and every host in
   your inventory (`inventory/`).
   - Only `--check --diff` and `verify.yml` are allowed, unless the human explicitly asks
     you to apply something in this conversation.
   - Never run `site.yml`, `restore.yml` or `reset.yml` against a real Obcell on your own.
     `reset.yml --check` (a preview) is fine. On a real Obcell only a human passes
     `obcell_reset_confirm`; in LXD test containers you may.
   - Never pass `-e obcell_confirm_host=…` to get past the "Right machine?" guard.
   - When you report drift, explain every changed task.
3. **Secrets.**
   - They live only in `secrets/<host>/` (git-ignored, mode 600). Never print, commit,
     paste or upload their values.
   - Tasks that handle secrets use `no_log: true` or `diff: false`.
   - The only key material allowed in git is the public 3GPP test SIM in
     `tests/lxd/group_vars/obcell.yml`.
4. **Long builds only on the test machine** (`tests/matrix.sh`), never on an Obcell box.
5. **Git.**
   - Work on a branch and keep commits small, with messages that say why.
   - Don't push, force-push or rewrite history unless asked.
   - Don't commit `tests/.work/`, `secrets/`, `.ansible/` or `activate`.
6. **Ask first** before anything outward-facing or hard to undo: deleting containers
   someone else made, changing GitHub settings, touching an Obcell's data, or installing system
   packages on a machine that isn't a test container.

## Picking up work

- Open work lives in `docs/tasks/NNN-*.md`; the format is in `docs/tasks/README.md`.
- Pick a task with `status: todo` whose `depends_on` tasks are `done`.
- If it says `needs_human: yes`, stop at the point it names and ask.
- While you work, set `status: in-progress`, and append dated notes under **Findings**:
  what you ran, the results summary table, and what you changed.
- Mark a task `done` only when every **Done when** item is true. If you're stuck, use
  `blocked`, with the reason.
- If you find new work, add a new task file rather than widening the current task.

## Commands

```bash
./bootstrap.sh && . ./activate               # controller venv (ansible-core picked by Python version)
ansible-lint                                  # must pass (production profile)
ansible-playbook --syntax-check site.yml verify.yml restore.yml reset.yml
python3 -m unittest discover -s tests/unit    # filter plugin tests
shellcheck -S warning -x bootstrap.sh install.sh tests/matrix.sh tests/lxd/*.sh

tests/lxd/setup-host.sh                       # once per test machine
tests/matrix.sh [--parallel] [--fresh] [RELEASE...]   # full install tests; read tests/.work/results/latest/summary.md
tests/lxd/run.sh 24.04 shell                  # poke around inside a test container
tests/lxd/radio-smoke.sh 24.04                # NG Setup + UE end to end (ZeroMQ only)

ansible-playbook site.yml --limit <host> --check --diff   # on the Obcell itself: drift report, read-only
```

## How the repo works

- **Host-specific values go only in `inventory/host_vars/<host>/main.yml`** (git-ignored; the
  tracked example is `inventory/host_vars/example/main.yml`). Everything else
  (web names, CORS lists, Caddy sites, CPU split, dashboards) is derived in `group_vars/all/`.
  Never hard-code a host name, IP or port in a role; use the variables in `web.yml` and
  `main.yml`.
- **Templates reproduce the live Obcell byte for byte.** After a change, `--check --diff` on
  the reference Obcell must show only intended changes. Since 2026-11-21 it matches the repo
  (`changed=0`; [task 007](docs/tasks/007-reference-apply-drift.md)).
- **Idempotence.** A second run must report `changed=0`. Avoid `get_url` (it reports
  changed in check mode; use `curl` with `creates:`), and give `command`/`shell` tasks
  `changed_when` or `creates`.
- **Templates that contain `{{ }}` themselves** (the Obcell CLI, control.py, radio_bridge.py,
  the Prometheus rules) use the `[= =]`, `[% %]` and `[# #]` delimiters, set in the task.
- **Shared task files** are in `roles/common/tasks/`. Include them with a relative path
  (`ansible.builtin.include_tasks: ../../common/tasks/git_patched.yml`); ansible-lint can't
  resolve `{{ playbook_dir }}` paths.
- **Tags.**
  - Tasks inside `include_tasks` do not inherit the include's tags. Use `import_tasks`
    when a guard must run under every tag.
  - Tag read-only fact tasks that templates need `always`.
- **Copying a directory with executables** needs `mode: preserve`.
- **Ubuntu releases:** see `docs/ubuntu-releases.md`, including how to add one.
  Release-specific choices are variables (`mongodb_repo_release`, `mongodb_version`, the SDR
  profile's `myriadrf_ppa`), never `when:` branches spread across roles.
- **A new radio** means a new entry in `group_vars/all/sdr.yml`.

## Traps already found (don't rediscover them)

- **CPU counts:** `ansible_processor_vcpus` counts host CPUs inside containers. The CPU
  split uses `obcell_cpus` (PID 1's `Cpus_allowed_list`).
- **Docker NAT:** never run `netfilter-persistent reload` on an Obcell. It flushes Docker's NAT
  rules. The base role writes `rules.v4` and adds the live rule itself.
- **PPAs:** `apt_repository` creates duplicate PPA list files when the URL differs by a
  trailing slash. `roles/common/tasks/ppa.yml` greps for the PPA first.
- **Cookies:** Authelia cookies are per host name, and browsers share cookies across ports.
  Homepage's `custom.js` rewrites links to the host name the page was opened on.
- **Open5GS WebUI:** it listens on 127.0.0.1:9999 only. Browsers use Caddy + Authelia on :9443.
- **Docker in LXD:** see "What the test containers need" in `docs/testing.md`.
- **`pkill -f pattern` inside `bash -c "…"`** also matches that shell's own command line.
  Use `pkill -f "[a]pps/gnb/gnb"`.
- **`cmd | grep -q` under `set -o pipefail`** fails at random (exit 141) when `cmd` writes
  more after grep has exited, e.g. `lxc info`. Ask for the value directly
  (`lxc list "^name$" --format csv -c s`) or use `grep … >/dev/null`.
- **`ansible_connection: local`** changes the machine it runs on. The "Right machine?"
  guard (`tasks/right_host.yml`) stops a run on the wrong box. Don't weaken it.

## The Obcell box at runtime

The generated runbook on an Obcell is `~/obcell/README.md`. It covers addresses, ports, files,
services and troubleshooting. The `obcell` CLI there is generated from
`roles/obcell_cli/templates/obcell.j2`.
