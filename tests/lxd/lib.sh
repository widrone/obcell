# shellcheck shell=bash
# Shared by the test scripts (source it; not executable on its own).

# Ubuntu LTS releases the Obcell is tested on, and the LXD container used for each.
OBCELL_TEST_RELEASES=(22.04 24.04 26.04)
container_for() {
  case "$1" in
    22.04) echo obcell-jammy ;;
    24.04) echo obcell-noble ;;
    26.04) echo obcell-resolute ;;
    *) echo "unknown release '$1' (known: ${OBCELL_TEST_RELEASES[*]})" >&2; return 2 ;;
  esac
}

# Controller venv made by ./bootstrap.sh
OBCELL_ANSIBLE_VENV=${OBCELL_ANSIBLE_VENV:-$HOME/.local/share/obcell-ansible}
export PATH="$OBCELL_ANSIBLE_VENV/bin:$PATH"

die() { echo "error: $*" >&2; exit 1; }
