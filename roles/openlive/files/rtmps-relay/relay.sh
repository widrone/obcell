#!/bin/sh
# Pulls each RTMPS feed and pushes it, remuxed (no re-encode), into Strom's SRT listener on localhost.
# A feed is only pulled while its SRT listener exists, i.e. while the Open Live production is active.
#
# /config/feeds.conf, one feed per line:   <srt-port> <rtmps-url> [srt-passphrase]
# Blank lines and lines starting with # are ignored.

FEEDS=/config/feeds.conf

listening() {
  ss -lun "( sport = :$1 )" | grep -q ":$1"
}

relay() {
  port=$1
  url=$2
  passphrase=$3
  target="srt://127.0.0.1:${port}?mode=caller&latency=200000"
  [ -n "$passphrase" ] && target="${target}&passphrase=${passphrase}&pbkeylen=16"
  while true; do
    if listening "$port"; then
      echo "port $port: listener up, pulling feed"
      ffmpeg -hide_banner -loglevel warning -nostdin \
        -rw_timeout 15000000 -i "$url" \
        -map 0:v:0 -map 0:a:0? -c copy \
        -f mpegts "$target"
      echo "port $port: ffmpeg exited ($?), retrying"
      sleep 3
    else
      sleep 3
    fi
  done
}

[ -f "$FEEDS" ] || { echo "missing $FEEDS"; exit 1; }
grep -vE '^\s*(#|$)' "$FEEDS" | while read -r port url passphrase; do
  case "$url" in
    *REPLACE*) echo "port $port: placeholder URL, skipped" ;;
    *) relay "$port" "$url" "$passphrase" & ;;
  esac
done
wait
sleep infinity
