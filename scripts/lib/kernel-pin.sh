#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verify a device's kernel pin against the remote without a full clone.
# KERNEL_REF may be a branch or a tag. Exit: 0 ok, 3 mismatch, 2 bad args.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

load_device "${1:-}"
[ -n "${KERNEL_COMMIT:-}" ] || die "$DEVICE: KERNEL_COMMIT is empty; cannot verify" 3
require_cmd git

info "verifying $DEVICE pin $KERNEL_COMMIT on $KERNEL_REPO ($KERNEL_REF)"
if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] git ls-remote $KERNEL_REPO refs/heads/$KERNEL_REF refs/tags/$KERNEL_REF^{}"
  exit 0
fi

refsha=""
for ref in "refs/heads/$KERNEL_REF" "refs/tags/$KERNEL_REF^{}" "refs/tags/$KERNEL_REF"; do
  refsha="$(git ls-remote "$KERNEL_REPO" "$ref" 2>/dev/null | awk '{print $1}' | head -1)"
  [ -n "$refsha" ] && break
done
[ -n "$refsha" ] || die "$DEVICE: ref $KERNEL_REF not found on $KERNEL_REPO (branch or tag)" 3

if [ "$refsha" = "$KERNEL_COMMIT" ]; then
  info "pin matches $KERNEL_REF: $refsha"
elif git ls-remote "$KERNEL_REPO" 2>/dev/null | awk '{print $1}' | grep -qx "$KERNEL_COMMIT"; then
  info "pin is an older commit on the remote ($KERNEL_REF now $refsha); checkout stays pinned"
else
  die "$DEVICE: commit $KERNEL_COMMIT not found on $KERNEL_REPO" 3
fi

if [ -n "${KERNEL_ARCHIVE_SHA256:-}" ]; then
  info "archive checksum configured ($KERNEL_ARCHIVE_SHA256)"
else
  warn "KERNEL_ARCHIVE_SHA256 empty: tarball integrity not enforced"
fi
