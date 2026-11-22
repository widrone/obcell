#!/usr/bin/env bash
# Radio checks inside an LXD test container, ZeroMQ virtual radio only (no RF, ever):
#   1. ng_setup: start the gnb-n40 unit (sdr_type=zmq in the test vars) and wait for the AMF
#      to log "gNB-N2 accepted"; stop it again.
#   2. e2e (only if srsUE was built, srsue_enabled=true): run the band-3 ZMQ gNB
#      (~/gnb_zmq.yml) + srsUE (~/ue_zmq.conf), wait for the PDU session, ping the core
#      gateway from the UE namespace.
# Prints one "RESULT <check>=PASS|FAIL|SKIP" line per check; exit code 0 only if none failed.
#   tests/lxd/radio-smoke.sh [RELEASE]
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lxd/lib.sh
REL=${1:-22.04}
C=$(container_for "$REL") || exit 2
H=/home/ubuntu
GW=${OBCELL_TEST_UE_GATEWAY:-10.45.0.1}       # ue_pool_v4_gateway
cx() { lxc exec "$C" -- bash -c "$1"; }   # run in the container

# No `lxc info | grep -q` here: with pipefail, grep -q exiting early makes lxc info die of
# SIGPIPE (exit 141) on its long output, and a running container looks stopped.
[ "$(lxc list "^$C\$" --format csv -c s 2>/dev/null)" = RUNNING ] || die "container $C is not running"
# Safety: only ever start a gNB whose radio is the ZeroMQ driver, inside an LXD container.
for cfg in gnb_n40.yml gnb_zmq.yml; do
  if cx "test -f $H/$cfg"; then
    cx "grep -qE '^\s*device_driver:\s*zmq\s*$' $H/$cfg" || die "$cfg in $C is not a ZeroMQ config; refusing to start it"
  fi
done
cx 'systemd-detect-virt -c -q' || die "$C does not look like a container; refusing"

fails=0
result() { echo "RESULT $1=$2"; [ "$2" = FAIL ] && fails=$((fails + 1)); return 0; }

# ---------------------------------------------------------------- 1. NG Setup via the unit
echo "== ng_setup: gnb-n40 (ZeroMQ) -> AMF"
before=$(cx 'wc -l < /var/log/open5gs/amf.log')
cx 'systemctl reset-failed gnb-n40 2>/dev/null; systemctl start gnb-n40'
ok=FAIL
for _ in $(seq 60); do
  if cx "tail -n +$((before + 1)) /var/log/open5gs/amf.log | grep -q 'gNB-N2 accepted'"; then ok=PASS; break; fi
  sleep 2
done
cx 'systemctl stop gnb-n40; systemctl reset-failed gnb-n40 2>/dev/null; true'
[ $ok = FAIL ] && cx 'journalctl -u gnb-n40 --no-pager -n 30'
result ng_setup $ok
[ "$(cx 'systemctl is-enabled gnb-n40 2>/dev/null')" = enabled ] && { echo "gnb-n40 is enabled at boot (must not be)"; result gnb_not_enabled FAIL; } || result gnb_not_enabled PASS

# ---------------------------------------------------------------- 2. srsUE end to end
GNB=$(cx "ls $H/ocudu/build/apps/gnb/gnb 2>/dev/null")
UE=$(cx "ls $H/srsRAN_4G/build/srsue/src/srsue 2>/dev/null")
if [ -z "$UE" ] || ! cx "test -f $H/gnb_zmq.yml -a -f $H/ue_zmq.conf"; then
  echo "== e2e: srsUE not built (run with -e srsue_enabled=true)"
  result e2e SKIP
else
  echo "== e2e: ZMQ gNB (band 3) + srsUE -> PDU session -> ping $GW"
  # "[a]pps": the pattern must not match this bash -c command line itself.
  cx 'pkill -f "[a]pps/gnb/gnb"; pkill -f "[s]rsue/src/srsue"; ip netns add ue1 2>/dev/null; rm -f /tmp/e2e-gnb.log /tmp/e2e-ue.log; true'
  cx "cd /tmp && setsid -f $GNB -c $H/gnb_zmq.yml > /tmp/e2e-gnb.log 2>&1 < /dev/null"
  sleep 8
  cx "cd /tmp && setsid -f $UE $H/ue_zmq.conf > /tmp/e2e-ue.log 2>&1 < /dev/null"
  ok=FAIL
  for _ in $(seq 60); do
    if cx "grep -q 'PDU Session Establishment successful' /tmp/e2e-ue.log"; then ok=PASS; break; fi
    sleep 2
  done
  if [ $ok = PASS ]; then
    cx "grep -m1 'PDU Session Establishment successful' /tmp/e2e-ue.log"
    cx "ip netns exec ue1 ping -c 3 -W 2 $GW" || ok=FAIL
  else
    echo "--- gNB log"; cx 'tail -n 30 /tmp/e2e-gnb.log'
    echo "--- UE log";  cx 'tail -n 30 /tmp/e2e-ue.log'
  fi
  cx 'pkill -INT -f "[s]rsue/src/srsue"; pkill -INT -f "[a]pps/gnb/gnb"; sleep 3; pkill -9 -f "[s]rsue/src/srsue"; pkill -9 -f "[a]pps/gnb/gnb"; true'
  result e2e $ok
fi

[ $fails -eq 0 ]
