#!/usr/bin/env bash
# Test matrix: on each Ubuntu LTS, in its own LXD container (ZeroMQ radio, no RF):
#   install     site.yml from scratch (+ verify.yml)
#   idempotent  site.yml again must report changed=0
#   radio       tests/lxd/radio-smoke.sh: gNB NG Setup, srsUE end to end
# Results: tests/.work/results/<UTC time>/summary.md (+ logs per release); "latest" links to the newest.
# Run it on a test machine set up with tests/lxd/setup-host.sh, never on an Obcell box.
#
#   tests/matrix.sh [options] [RELEASE...]        default releases: 22.04 24.04 26.04
#     --controller inside   (default) each container bootstraps Ansible and installs itself,
#                           exactly like a new Obcell box (ansible-core picked by its Python)
#     --controller outside  this machine's venv drives the containers (LXD connection)
#     --parallel            all releases at once (each needs ~4 CPUs / 8 GiB to be quick)
#     --fresh               delete the containers first (true from-scratch run)
#     --no-srsue            don't build srsUE (the end-to-end UE check is then skipped)
#     --only PHASES         comma list of install,idempotent,radio (default: all)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/lxd/lib.sh

CTL=inside PAR=0 FRESH=0 SRSUE=1 PHASES=install,idempotent,radio RELS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --controller) CTL=$2; shift ;;
    --parallel) PAR=1 ;;
    --fresh) FRESH=1 ;;
    --no-srsue) SRSUE=0 ;;
    --only) PHASES=$2; shift ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"; exit 0 ;;
    2[0-9].04) RELS+=("$1") ;;
    *) die "unknown argument '$1' (see --help)" ;;
  esac
  shift
done
[ ${#RELS[@]} -gt 0 ] || RELS=("${OBCELL_TEST_RELEASES[@]}")
case $CTL in inside|outside) ;; *) die "--controller must be inside or outside" ;; esac
for r in "${RELS[@]}"; do container_for "$r" >/dev/null || exit 2; done
command -v lxc >/dev/null || die "LXD is not installed; run tests/lxd/setup-host.sh first"
[ "$CTL" = outside ] && { command -v ansible-playbook >/dev/null || die "no Ansible venv; run ./bootstrap.sh"; }
EXTRA=(); [ $SRSUE = 1 ] && EXTRA=(-e srsue_enabled=true)
want() { [[ ",$PHASES," == *",$1,"* ]]; }

TS=$(date -u +%Y%m%d-%H%M%S)
OUT=tests/.work/results/$TS
mkdir -p "$OUT"; ln -sfn "$TS" tests/.work/results/latest

# PLAY RECAP lines of one log, as "ok=N changed=N unreachable=N failed=N" (one per playbook run)
recaps() { grep -aE '^[a-z0-9-]+ +: ok=' "$1" 2>/dev/null | sed -E 's/^[^:]+: +//; s/ +skipped=.*//'; }
field() { sed -nE "s/.*$1=([0-9]+).*/\1/p" <<<"$2"; }
recap_ok() { [ -n "$1" ] && [ "$(field failed "$1")" = 0 ] && [ "$(field unreachable "$1")" = 0 ]; }
# The task that failed first, and its message (for the summary)
first_failure() {
  awk '/^TASK \[/{t=$0} /^(fatal|failed): /{if (!found) {print t; print}; found=1; next}
       found && /^    (msg|stderr):/{m=1; c=0}
       m && c<8 {print; c++} m && c>=8 {exit}' "$1" | cut -c1-240
}

run_one() {
  local rel=$1 d=$OUT/$1 c t0 inst=SKIP health=SKIP idem=SKIP ng=SKIP e2e=SKIP ver=""
  c=$(container_for "$rel"); mkdir -p "$d"; t0=$(date +%s)
  echo "[$rel] container $c, controller $CTL, logs in $d"
  [ $FRESH = 1 ] && { lxc delete -f "$c" >/dev/null 2>&1 || true; }

  if want install; then
    OBCELL_TEST_CONTROLLER=$CTL tests/lxd/run.sh "$rel" "${EXTRA[@]}" > "$d/install.log" 2>&1
    mapfile -t r < <(recaps "$d/install.log")
    recap_ok "${r[0]:-}" && inst=PASS || inst=FAIL
    { [ $inst = PASS ] && recap_ok "${r[1]:-}"; } && health=PASS || health=FAIL
    [ $inst = FAIL ] && health=SKIP
    [ $inst = FAIL ] && first_failure "$d/install.log" > "$d/first-failure.txt"
    echo "[$rel] install $inst, health $health"
  fi
  if want idempotent && [ "$inst" != FAIL ]; then
    OBCELL_TEST_CONTROLLER=$CTL tests/lxd/run.sh "$rel" "${EXTRA[@]}" > "$d/idempotent.log" 2>&1
    mapfile -t r < <(recaps "$d/idempotent.log")
    { recap_ok "${r[0]:-}" && [ "$(field changed "${r[0]}")" = 0 ]; } && idem=PASS || idem=FAIL
    [ $idem = FAIL ] && awk '/^TASK \[/{t=$0} /^changed: /{print t" :: "$0}' "$d/idempotent.log" \
      | cut -c1-200 > "$d/not-idempotent.txt"
    echo "[$rel] idempotent $idem"
  fi
  if want radio && [ "$inst" != FAIL ]; then
    tests/lxd/radio-smoke.sh "$rel" > "$d/radio.log" 2>&1
    ng=$(sed -nE 's/^RESULT ng_setup=//p' "$d/radio.log"); ng=${ng:-FAIL}
    e2e=$(sed -nE 's/^RESULT e2e=//p' "$d/radio.log"); e2e=${e2e:-FAIL}
    echo "[$rel] ng_setup $ng, e2e $e2e"
  fi
  ver=$(grep -aom1 'ansible \[core [0-9.]*\]' "$d/install.log" 2>/dev/null | sed 's/ansible \[core \(.*\)\]/\1/')
  [ -z "$ver" ] && [ "$CTL" = outside ] && ver=$(ansible --version 2>/dev/null | sed -nE '1s/.*core ([0-9.]+).*/\1/p')
  cat > "$d/result.env" <<EOF
release=$rel
container=$c
controller=$CTL
ansible_core=${ver:-?}
install=$inst
health=$health
idempotent=$idem
ng_setup=$ng
e2e=$e2e
minutes=$(( ($(date +%s) - t0 + 59) / 60 ))
EOF
}

if [ $PAR = 1 ]; then
  for r in "${RELS[@]}"; do run_one "$r" & done; wait
else
  for r in "${RELS[@]}"; do run_one "$r"; done
fi

# ---------------------------------------------------------------- summary.md
{
  echo "# Test matrix $TS"
  echo
  echo "Machine: $(hostname), $(nproc) CPUs, $(free -g | awk '/^Mem:/{print $2}') GiB RAM, LXD $(lxc version 2>/dev/null | awk '/Server/{print $3}')."
  echo "Repo: $(git rev-parse --short HEAD 2>/dev/null)$(git diff --quiet 2>/dev/null || echo ' + uncommitted changes'). Options: controller=$CTL fresh=$FRESH srsue=$SRSUE phases=$PHASES."
  echo
  echo "| Release | ansible-core | Install | Health | Idempotent | NG Setup | UE end-to-end | Minutes |"
  echo "|---|---|---|---|---|---|---|---|"
  for r in "${RELS[@]}"; do
    # shellcheck disable=SC1090,SC2154  # result.env is written by run_one above
    (. "$OUT/$r/result.env"; echo "| $release ($container) | $ansible_core ($controller) | $install | $health | $idempotent | $ng_setup | $e2e | $minutes |")
  done
  for r in "${RELS[@]}"; do
    for f in first-failure.txt not-idempotent.txt; do
      [ -s "$OUT/$r/$f" ] || continue
      echo; echo "## $r: ${f%.txt}"; echo; echo '```'; cat "$OUT/$r/$f"; echo '```'
    done
  done
  echo
  echo "Logs: \`$OUT/<release>/\` (install.log, idempotent.log, radio.log)."
} > "$OUT/summary.md"
cat "$OUT/summary.md"
! grep -qE '\| FAIL \|' "$OUT/summary.md"
