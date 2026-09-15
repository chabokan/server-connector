#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export INSTALL_LOG="$TEST_DIR/install.log"
source "$REPO_DIR/lib/docker.sh"

git init -q --bare "$TEST_DIR/origin.git"
git init -q "$TEST_DIR/source"
git -C "$TEST_DIR/source" config user.name Test
git -C "$TEST_DIR/source" config user.email test@example.com
printf 'first\n' > "$TEST_DIR/source/version.txt"
git -C "$TEST_DIR/source" add version.txt
git -C "$TEST_DIR/source" commit -qm first
git -C "$TEST_DIR/source" remote add origin "$TEST_DIR/origin.git"
git -C "$TEST_DIR/source" push -q -u origin HEAD

prepare_node_manager_checkout "$TEST_DIR/origin.git" "$TEST_DIR/manager"
printf 'saved database\n' > "$TEST_DIR/manager/sql_app.db"
printf 'second\n' > "$TEST_DIR/source/version.txt"
git -C "$TEST_DIR/source" commit -qam second
git -C "$TEST_DIR/source" push -q
prepare_node_manager_checkout "$TEST_DIR/origin.git" "$TEST_DIR/manager"

[[ "$(cat "$TEST_DIR/manager/sql_app.db")" == 'saved database' ]]
[[ "$(cat "$TEST_DIR/manager/version.txt")" == 'second' ]]
printf 'local edit\n' > "$TEST_DIR/manager/version.txt"
printf 'third\n' > "$TEST_DIR/source/version.txt"
git -C "$TEST_DIR/source" commit -qam third
git -C "$TEST_DIR/source" push -q
if (prepare_node_manager_checkout "$TEST_DIR/origin.git" "$TEST_DIR/manager") > "$TEST_DIR/dirty.log" 2>&1; then
    printf 'expected a conflicting local change to block the update\n' >&2
    exit 1
fi
[[ "$(cat "$TEST_DIR/manager/sql_app.db")" == 'saved database' ]]
[[ "$(cat "$TEST_DIR/manager/version.txt")" == 'local edit' ]]

TOKEN='token with a single quote '\'' and spaces'
HUB_URL=hub.example.com
write_runtime_env "$TEST_DIR/runtime.env"
source "$TEST_DIR/runtime.env"
[[ "$TOKEN" == 'token with a single quote '\'' and spaces' ]]
printf 'checkout update preserves database: ok\n'
