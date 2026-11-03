#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python3 /Users/user/.codex/helpers/storage_guard.py --check-heavy
pg_bin=/opt/homebrew/opt/postgresql@17/bin
mkdir -p "$repo_root/work"
data_dir=$(mktemp -d "$repo_root/work/social-pg-XXXXXX")
socket_dir=$(mktemp -d /private/tmp/venue-pulse-XXXXXX)
cleanup() {
  "$pg_bin/pg_ctl" -D "$data_dir" -m immediate stop >/dev/null 2>&1 || true
  rm -rf -- "$data_dir" "$socket_dir"
}
trap cleanup EXIT HUP INT TERM
"$pg_bin/initdb" -D "$data_dir" --auth-local=trust --auth-host=reject --no-locale --encoding=UTF8 >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -l "$data_dir/test.log" -o "-F -k $socket_dir -p 55440 -c listen_addresses='' -c max_connections=16 -c shared_buffers=8MB" -w start >/dev/null
"$pg_bin/createdb" -h "$socket_dir" -p 55440 pulse_test
python3 "$repo_root/tests/social_database_test.py" "$socket_dir" "$repo_root"
