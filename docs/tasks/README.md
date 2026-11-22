# Tasks

Open work, one file per task, written so that a person or an agent can pick it up cold.

| # | Task | Where | Human needed | Depends on |
|---|---|---|---|---|
| 001 | [Set up the test machine](001-test-machine.md) | test machine | to provide the machine | – |
| 002 | [Baseline: 22.04 still passes](002-baseline-2204.md) | test machine | no | 001 |
| 003 | [Make the Obcell install on Ubuntu 24.04](003-ubuntu-2404.md) | test machine | no | 002 |
| 004 | [Make the Obcell install on Ubuntu 26.04](004-ubuntu-2604.md) | test machine | no | 002 |
| 005 | [Prove the virtual-phone end-to-end check](005-ue-e2e.md) | test machine | no | 002 |
| 006 | [Get GitHub Actions green](006-ci-green.md) | anywhere | to create the repo | – |
| 007 | [Apply the pending changes on the reference Obcell](007-reference-apply-drift.md) | reference Obcell | **yes** | – |
| 008 | [Reboot test on the reference Obcell](008-reference-reboot.md) | reference Obcell | **yes** | 007 |
| 009 | [Plan the MongoDB 6.0 and Node 20 upgrades](009-eol-upgrades.md) | test machine | to approve on an Obcell | 003 |
| 010 | [Optional: encrypt secrets with ansible-vault](010-secrets-vault.md) | anywhere | **yes** (key handling) | – |
| 011 | [OwnTracks location tracking](011-owntracks.md) | test machine, reference Obcell | **yes** (apply, real phones) | – |
| 012 | [OwnTracks from the open internet (Funnel), deferred](012-owntracks-funnel.md) | reference Obcell | **yes** (tailnet policy; deferred by the owner) | 011 |

## Format

Each file starts with a small header, then fixed sections:

```markdown
---
id: 003
title: Make the Obcell install on Ubuntu 24.04
status: todo          # todo | in-progress | blocked | done
where: test machine   # test machine | reference Obcell | anywhere
needs_human: no       # yes = stop and ask at the point the task names
depends_on: [002]
---

## Goal          what should be true afterwards, in one or two sentences
## Context       what is known already, and links
## Steps         a suggested route (deviate if you find a better one, and say why)
## Done when     checkable acceptance criteria
## Findings      append-only, dated notes: what was run, result tables, what changed
```

Rules:

- Keep the table above in sync with the files' `status`.
- **Findings** is append-only, so the history of attempts stays readable.
- Record results as the `summary.md` table from `tests/matrix.sh`, plus the commit that
  fixed things. Don't paste full logs.
- Never write secret values in a task file.
