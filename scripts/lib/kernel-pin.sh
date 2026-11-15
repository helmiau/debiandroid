#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verify a device's kernel pin against the remote without a full clone.
# Usage: kernel-pin.sh <codename> [--dry-run]
# Exit: 0 pinned commit exists, 3 mismatch/missing, 2 bad arguments.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

load_device "${1:-}"
[ -n "${KERNEL_COMMIT:-}" ] || die "$DEVICE: KERNEL_COMMIT is empty; cannot verify" 3
require_cmd git

info "verifying $DEVICE pin $KERNEL_COMMIT on $KERNEL_REPO ($KERNEL_REF)"
if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] git ls-remote $KERNEL_REPO refs/heads/$KERNEL_REF"
  exit 0
fi
refsha="$(git ls-remote "$KERNEL_REPO" "refs/heads/$KERNEL_REF" 2>/dev/null | awk '{print $1}' | head -1)"
[ -n "$refsha" ] || die "$DEVICE: branch $KERNEL_REF not found on $KERNEL_REPO" 3
if [ "$refsha" = "$KERNEL_COMMIT" ]; then
  info "pin matches branch head: $refsha"
elif git ls-remote "$KERNEL_REPO" 2>/dev/null | grep -q "^$KERNEL_COMMIT"; then
  info "pin exists on the remote but is not the branch head ($refsha); checkout stays pinned"
else
  die "$DEVICE: commit $KERNEL_COMMIT not found on $KERNEL_REPO" 3
fi

if [ -n "${KERNEL_ARCHIVE_SHA256:-}" ]; then
  info "archive checksum configured ($KERNEL_ARCHIVE_SHA256)"
else
  warn "KERNEL_ARCHIVE_SHA256 empty: tarball integrity not enforced"
fi
