#!/usr/bin/env bash
# Obcell installer: run on a fresh Ubuntu box, as the normal user (not root):
#
#   curl -fsSL https://raw.githubusercontent.com/widrone/obcell/main/install.sh | bash
#
# It installs git, clones (or updates) the repo in ~/obcell-src, sets up Ansible, writes a
# starter config for THIS box (radio detected from USB), and asks before it builds anything.
# Safe to run again. It never puts the cell on air: that is always `obcell onair`, by hand.
#
# Settings (environment variables, all optional):
#   OBCELL_SRC=~/obcell-src     where the repo goes
#   OBCELL_REPO=<git url>       clone from somewhere else (a fork, a local path)
#   OBCELL_BRANCH=main
#   OBCELL_NAME=<name>          name of this Obcell (default: the hostname)
#   OBCELL_BUILD=yes|no         build without asking / don't ask (default: ask)
set -euo pipefail

main() {
  local src=${OBCELL_SRC:-$HOME/obcell-src}
  local repo=${OBCELL_REPO:-https://github.com/widrone/obcell.git}
  local branch=${OBCELL_BRANCH:-main}
  local name=${OBCELL_NAME:-$(hostname -s)}
  local tty=/dev/tty; [ -r /dev/tty ] && [ -w /dev/tty ] || tty=""

  say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
  die() { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
  ask() {  # ask "question" default -> echoes y or n
    local a=""
    if [ -n "$tty" ]; then read -r -p "$1 " a <"$tty" || true; fi
    a=${a:-$2}; case $a in [yY]*) echo y ;; *) echo n ;; esac
  }

  # 1. Checks
  [ "$(id -u)" -ne 0 ] || die "run this as the user who will own the Obcell, not as root (it uses sudo itself)"
  command -v sudo >/dev/null || die "sudo is needed"
  . /etc/os-release 2>/dev/null || true
  if [ "${ID:-}" != ubuntu ]; then
    die "Obcell needs Ubuntu Server LTS (found: ${PRETTY_NAME:-unknown})"
  fi
  case ${VERSION_ID:-} in
    22.04) ;;
    24.04|26.04) say "Ubuntu $VERSION_ID: tested in containers with the virtual radio; the reference Obcell runs 22.04" ;;
    *) die "Ubuntu ${VERSION_ID:-?} is not supported (22.04, 24.04 or 26.04)" ;;
  esac
  [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Obcell name '$name' must be lower-case letters, digits and '-' (set OBCELL_NAME)"

  local ask_pass=()
  if ! sudo -n true 2>/dev/null; then
    say "sudo needs your password (asked once now, and once more by Ansible for the build)"
    [ -n "$tty" ] || die "no terminal to ask for the sudo password on"
    sudo -v <"$tty"
    ask_pass=(-K)
  fi

  # 2. git + the repo
  if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
    say "Installing git and curl"
    sudo apt-get update -qq && sudo apt-get install -y -qq git curl
  fi
  if [ -d "$src/.git" ]; then
    say "Updating $src"
    git -C "$src" pull --ff-only -q || die "could not update $src (local changes?); fix it or set OBCELL_SRC"
  elif [ -e "$src" ]; then
    die "$src exists but isn't a git checkout; move it away or set OBCELL_SRC"
  else
    say "Cloning $repo into $src"
    git clone -q --branch "$branch" "$repo" "$src"
  fi
  cd "$src"

  # 3. Ansible
  say "Setting up Ansible (a Python venv, ~2 minutes the first time)"
  ./bootstrap.sh
  # shellcheck disable=SC1091
  . ./activate

  # 4. This box in the inventory
  local hv=inventory/host_vars/$name/main.yml inv=inventory/$name.yml
  if ansible-inventory --host "$name" >/dev/null 2>&1; then
    say "'$name' is already in the inventory; keeping its settings ($hv)"
  else
    say "Adding this box to the inventory as '$name'"
    write_host_files "$name" "$inv" "$hv"
  fi

  # 5. Build. The installer runs on the box it sets up, so a name that differs from the
  # hostname (OBCELL_NAME) is confirmed here for the playbook's "Right machine?" guard.
  local extra=("${ask_pass[@]}")
  [ "$name" = "$(hostname -s)" ] || extra+=(-e "obcell_confirm_host=$name")
  local cmd="cd $src && . ./activate && ansible-playbook site.yml --limit $name ${extra[*]}"
  cat <<EOF

Ready. This box's settings are in $src/$hv
(radio, cell, Tailscale, time zone; docs/configuration.md explains every setting).

The build installs the 5G core, the gNB, the web stacks and monitoring, takes about an
hour the first time, and can be re-run at any time. It never puts the cell on air.

  Build:        $cmd
  Health check: cd $src && . ./activate && ansible-playbook verify.yml --limit $name ${ask_pass[*]}

EOF
  local go=${OBCELL_BUILD:-}
  if [ -z "$go" ]; then
    go=$(ask "Build now with these settings? [y/N]" n)
  fi
  case $go in
    y|yes)
      local in=${tty:-/dev/null}
      ansible-playbook site.yml --limit "$name" "${extra[@]}" <"$in"
      ansible-playbook verify.yml --limit "$name" "${ask_pass[@]}" <"$in"
      cat <<EOF

Done. On this box: 'obcell status' (log in again first, or run ~/obcell/obcell status),
and the portal at https://$name.local/ (login details in ~/openlive/CREDENTIALS.txt).
EOF
      ;;
    *) echo "Not building now. Edit the settings if you like, then run the build command above." ;;
  esac
}

# The starter inventory entry + host_vars for this machine, with what we can detect.
write_host_files() {
  local name=$1 inv=$2 hv=$3
  local iface tz sdr="zmq" serial="" note
  iface=$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  # Same USB ids as roles/monitoring/files/sdr-exporter/exporter.py
  local d id
  for d in /sys/bus/usb/devices/*; do
    [ -r "$d/idVendor" ] || continue
    id="$(cat "$d/idVendor"):$(cat "$d/idProduct")"
    case $id in
      0403:601f) sdr=limesdr_mini ;;
      1d50:6108) sdr=limesdr_usb ;;
      2500:0020|2500:0021|2500:0022) sdr=usrp_b2xx ;;
      *) continue ;;
    esac
    serial=$(cat "$d/serial" 2>/dev/null || true)
    break
  done
  if [ "$sdr" = zmq ]; then
    note="no supported SDR found on USB: 'zmq' is a virtual radio (nothing transmits). Plug in the SDR and set sdr_type."
  else
    note="detected on USB."
  fi

  mkdir -p "$(dirname "$hv")"
  cat >"$inv" <<EOF
# Written by install.sh: this machine, managed locally.
all:
  children:
    obcell:
      hosts:
        $name:
          ansible_connection: local
          ansible_python_interpreter: /usr/bin/python3
EOF
  cat >"$hv" <<EOF
# $name: written by install.sh on $(date +%F). Edit freely; docs/configuration.md explains
# every setting, and inventory/host_vars/example/main.yml is a full example.
obcell_user: $USER
obcell_name: $name
obcell_lan_iface: ${iface:-eth0}
obcell_timezone: ${tz:-Etc/UTC}

# Remote access over Tailscale (optional): set true and give the box's tailnet name.
tailscale_enabled: false
obcell_tailnet_name: ""

# Radio: $note
# Types: limesdr_mini, limesdr_usb, usrp_b2xx, usrp_x3xx, zmq (group_vars/all/sdr.yml).
sdr_type: $sdr
sdr_serial: "$serial"

# The cell. These are the defaults (band n40, 2350 MHz, 20 MHz). Only transmit on a band
# and frequency you are licensed for.
# cell:
#   band: 40
#   dl_arfcn: 470000
#   bandwidth_mhz: 20
#   scs_khz: 30
#   pci: 1
#   srate: 23.04
#   tx_gain: null       # null = the SDR profile's default
#   rx_gain: null

rtlsdr_enabled: true    # OpenWebRX spectrum view, if an RTL-SDR dongle is plugged in
EOF
  echo "  wrote $inv and $hv (radio: $sdr${serial:+, serial $serial})"
}

main "$@"; exit
