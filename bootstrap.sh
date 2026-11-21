#!/usr/bin/env bash
# Set up the control machine (the Obcell itself, or a laptop that manages it over SSH):
# Python venv with Ansible + the collections the playbooks use. Safe to re-run.
#   ./bootstrap.sh && . ./activate
set -euo pipefail
cd "$(dirname "$0")"
VENV=${OBCELL_ANSIBLE_VENV:-$HOME/.local/share/obcell-ansible}
if ! python3 -c 'import venv, ensurepip' 2>/dev/null; then
  sudo apt-get update -qq && sudo apt-get install -y -qq python3-venv python3-pip git
fi
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q -r requirements.txt
"$VENV/bin/ansible-galaxy" collection install -r requirements.yml >/dev/null
printf 'export PATH=%s/bin:$PATH\n' "$VENV" > activate
echo "ready: . ./activate && ansible-playbook site.yml --check --diff"
