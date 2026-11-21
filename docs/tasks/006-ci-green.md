---
id: 006
title: Get GitHub Actions green
status: done
where: anywhere
needs_human: yes      # a human creates the GitHub repo and pushes
depends_on: []
---

## Goal

`.github/workflows/checks.yml` passes on GitHub for every push: syntax check, ansible-lint,
unit tests and shellcheck, on Python 3.10, 3.12 and 3.14 (ansible-core 2.17 and 2.20).

## Context

- The workflow was written on 2026-11-21 and has **never run on GitHub**.
- Locally (reference Obcell, Python 3.10, ansible-core 2.17) all the same commands pass: syntax check
  on all three inventories, `ansible-lint` (production profile), the unit tests, and
  shellcheck.
- Untested: `bootstrap.sh` on the Python 3.12/3.14 runners (ansible-core 2.20 resolution,
  `bcrypt<4.1` wheels, passlib), and newer ansible-lint rules under 2.20.

## Steps

1. Human: create the GitHub repo (private is recommended: the inventory names the real Obcell,
   its tailnet and its SDR serial) and push.
2. Read the Actions results, fix in a branch, open a PR.
3. Lint findings that only appear under 2.20: fix them so 2.17 still passes too. Add to
   `.ansible-lint`'s skip list only with a comment saying why.

## Done when

- [x] All jobs are green on the default branch.
- [x] No `skip_list` additions without a reason.

## Findings

### 2026-11-21

- Private repo created (github.com/widrone/obcell) and `main` pushed (a4be03d). The first run of
  `checks` ([run 44901396699](https://github.com/widrone/obcell/actions/runs/44901396699))
  passed with no changes needed:

  | Job | Result |
  |---|---|
  | ansible (Python 3.10, ansible-core 2.17) | pass |
  | ansible (Python 3.12, ansible-core 2.20) | pass |
  | ansible (Python 3.14, ansible-core 2.20) | pass |
  | shellcheck | pass |

- So `bootstrap.sh`, syntax check, ansible-lint and the unit tests work under ansible-core 2.20.
  No `skip_list` changes.
- The only warning: `actions/checkout@v4` and `actions/setup-python@v5` target Node 20, which
  GitHub is retiring. Bumped both to `@v7` (Node 24).

