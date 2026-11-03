#!/bin/sh
# Sólo PostgreSQL descartable por socket. No lee .env.local ni llama al banco.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# control de espacio en disco (ayudante local opcional)
g=/Users/user/.codex/helpers/storage_guard.py; [ -n "${SIN_CONTROL_DISCO:-}" ] || [ ! -f "$g" ] || python3 "$g" --check-heavy
pg_bin=${BANECO_TEST_PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}
mkdir -p "$repo_root/work"
data_dir=$(mktemp -d "$repo_root/work/baneco-pg-XXXXXX")
socket_dir=$(mktemp -d /private/tmp/venue-baneco-XXXXXX)
cleanup() {
  "$pg_bin/pg_ctl" -D "$data_dir" -m immediate stop >/dev/null 2>&1 || true
  rm -rf -- "$data_dir" "$socket_dir"
}
trap cleanup EXIT HUP INT TERM
"$pg_bin/initdb" -D "$data_dir" --auth-local=trust --auth-host=reject --no-locale --encoding=UTF8 >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -l "$data_dir/test.log" -o "-F -k $socket_dir -p 55439 -c listen_addresses='' -c max_connections=12 -c shared_buffers=8MB" -w start >/dev/null
"$pg_bin/createdb" -h "$socket_dir" -p 55439 baneco_test
python3 "$repo_root/db/functions/baneco/tests/database_test.py" "$socket_dir" "$repo_root" \
  "$repo_root/supabase/migrations/20261031172015_baneco_seguro.sql"
