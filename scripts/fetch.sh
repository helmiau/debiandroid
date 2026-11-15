#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Download a release asset and verify its SHA-256 before use.
# Usage: fetch.sh --backend debian|ubuntu|prebuilt --channel snapshot|stable
#                 [--tag v0.1.0] [--repo owner/name] [--verify|--no-verify] [--dry-run]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

BACKEND=""; CHANNEL="stable"; TAG=""; REPO="${DEBIANDROID_REPO:-helmiau/debiandroid}"; VERIFY=1
for arg in "$@"; do
  case "$arg" in
    --backend=*) BACKEND="${arg#*=}" ;;
    --channel=*) CHANNEL="${arg#*=}" ;;
    --tag=*) TAG="${arg#*=}" ;;
    --repo=*) REPO="${arg#*=}" ;;
    --verify) VERIFY=1 ;;
    --no-verify) VERIFY=0 ;;
  esac
done
# Support the space-separated form too.
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) BACKEND="${2:-}"; shift 2 ;;
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

case "$BACKEND" in debian|ubuntu|prebuilt) ;; *) usage_die "--backend must be debian, ubuntu, or prebuilt" ;; esac
case "$CHANNEL" in snapshot|stable) ;; *) usage_die "--channel must be snapshot or stable" ;; esac
if [ -z "$TAG" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    TAG="<latest>"
  else
    TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
          | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$TAG" ] || die "cannot resolve the latest release tag for $REPO"
  fi
fi
ASSET="rootfs-${BACKEND}-arm64-${CHANNEL}-${TAG}.tar.zst"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
DEST="$CACHE_DIR/releases/$TAG"
run mkdir -p "$DEST"

info "release  $TAG"
info "asset    $ASSET"
info "verify   $VERIFY"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] curl -fL -o $DEST/$ASSET $URL"
  log "[dry-run] curl -fL -o $DEST/SHA256SUMS https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS"
  exit 0
fi

require_cmd curl
run curl -fL --retry 3 -o "$DEST/$ASSET" "$URL"
run curl -fL --retry 3 -o "$DEST/SHA256SUMS" "https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS"

if [ "$VERIFY" = "1" ]; then
  ( cd "$DEST" && grep " ${ASSET}\$" SHA256SUMS >/dev/null 2>&1 ) || die "asset not listed in SHA256SUMS"
  ( cd "$DEST" && sha256sum -c <(grep " ${ASSET}\$" SHA256SUMS) ) || die "checksum verification failed for $ASSET"
  info "checksum OK: $ASSET"
fi
info "saved: $DEST/$ASSET"
