#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verify that a kernel fragment took effect in a merged .config.
#
#   scripts/lib/kconfig-check.sh <merged.config> <fragment> [more fragments...]
#
# Kconfig silently drops an option when the symbol does not exist in the tree or
# when its dependencies are unmet; merge_config.sh only prints a warning, and
# build-kernel.sh discards that output. A dropped CONFIG_CGROUP_DEVICE is then
# discovered after a 40-minute build, on the device, when Docker refuses to start.
#
# Only lines of the form CONFIG_X=y or CONFIG_X=m are checked. Comments, blank
# lines, CONFIG_X=n and CONFIG_X="string" are ignored: a fragment that turns
# something off, or sets a value, is checked by the compiler, not here.
#
# Exit codes: 0 every requested option is present with the same value,
#             3 something is missing, 2 bad arguments.
set -euo pipefail

CONFIG="${1:-}"
shift || true
[ -n "$CONFIG" ] || { echo "usage: kconfig-check.sh <merged.config> <fragment>..." >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "kconfig-check: no such file: $CONFIG" >&2; exit 2; }
[ "$#" -ge 1 ] || { echo "usage: kconfig-check.sh <merged.config> <fragment>..." >&2; exit 2; }

cfgname="$(basename "$CONFIG")"
missing=0
for fragment in "$@"; do
  [ -f "$fragment" ] || { echo "kconfig-check: no such fragment: $fragment" >&2; exit 2; }
  fragname="$(basename "$fragment")"
  while IFS= read -r line; do
    case "$line" in
      CONFIG_*=y|CONFIG_*=m) ;;
      *) continue ;;
    esac
    key="${line%%=*}"
    got="$(grep -m1 -E "^${key}=[ym]$" "$CONFIG" || true)"
    if [ -z "$got" ]; then
      printf 'kconfig-check: %s: %s is not enabled in %s\n' "$fragname" "$key" "$cfgname" >&2
      missing=$((missing + 1))
    elif [ "$got" != "$line" ]; then
      printf 'kconfig-check: %s: requested %s, merged config has %s\n' "$fragname" "$line" "$got" >&2
      missing=$((missing + 1))
    fi
  done < "$fragment"
done

if [ "$missing" -ne 0 ]; then
  printf 'kconfig-check: %d option(s) did not survive the merge; the fragment references a symbol the tree does not have, or dependencies are unmet\n' "$missing" >&2
  exit 3
fi
exit 0
