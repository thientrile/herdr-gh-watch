#!/bin/sh
# Starts the webhook receiver detached; startup hooks are one-shot, not daemons.
state="${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr-gh-watch}"
mkdir -p "$state"
pidfile="$state/receiver.pid"
alive() { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }
case "$1" in
  --status) alive && echo "running pid $(cat "$pidfile")" || echo "not running"; exit 0 ;;
  --restart) alive && kill "$(cat "$pidfile")" 2>/dev/null; sleep 1 ;;
esac
alive && exit 0
cd "$(dirname "$0")" || exit 1
nohup python3 -I receiver.py >>"$state/receiver.log" 2>&1 &
echo $! >"$pidfile"
