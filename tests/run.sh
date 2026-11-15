#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Test entry point. Uses bats when available, otherwise runs the static checks.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
echo "== syntax check =="
for f in scripts/*.sh scripts/lib/*.sh scripts/rootfs/*.sh installer/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" || { echo "FAIL syntax: $f"; fail=1; }
done
echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh scripts/lib/*.sh scripts/rootfs/*.sh || fail=1
else
  echo "shellcheck not installed; skipped"
fi
echo "== bats =="
if command -v bats >/dev/null 2>&1; then
  bats tests/*.bats || fail=1
else
  echo "bats not installed; skipped"
fi
exit "$fail"
