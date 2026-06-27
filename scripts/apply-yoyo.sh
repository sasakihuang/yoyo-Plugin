#!/usr/bin/env bash
# yoyo Plugin — build-time transform for a CodexPlusPlus fork.
# Idempotent + self-checking. Run on a CLEAN checkout BEFORE building.
#   1. Disables in-app ads (推荐内容) at the data source.
#   2. Points the in-app updater at YOUR fork's releases.
#   3. Rebrands visible "Codex++" -> "yoyo Plugin" (app/window/UI/installers).
# Internal ids (codex-plus-plus binaries, CodexPlusPlus provider, codex-plus-*
# CSS) are left untouched so upstream merges stay conflict-free. If an anchor
# is gone upstream, it EXITS NON-ZERO so the build fails loudly (never ships ads).
# Usage: REPO_SLUG="you/yoyo-Plugin" BRAND="yoyo Plugin" bash scripts/apply-yoyo.sh
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-${GITHUB_REPOSITORY:-OWNER/yoyo-Plugin}}"
BRAND="${BRAND:-yoyo Plugin}"
ASSET_PREFIX="${ASSET_PREFIX:-YoyoPlugin}"

ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

_rep() {  # <file> <FROM> <TO> : literal, global, idempotent, anchor-checked
  local f="$1"
  [ -f "$f" ] || { echo "MISSING FILE: $f" >&2; exit 2; }
  FROM="$2" TO="$3" FILE="$f" perl -0777 -i -pe '
    BEGIN { $from = $ENV{FROM}; $to = $ENV{TO}; $file = $ENV{FILE}; }
    if (index($_, $from) >= 0) { s/\Q$from\E/$to/g; }
    elsif (index($_, $to) >= 0) { }
    else { die "ANCHOR MISSING in $file: $from\n(upstream changed; update apply-yoyo.sh)\n"; }
  ' "$f"
}

echo ">> [1/5] disable in-app ads (推荐内容)"
_rep crates/codex-plus-core/src/ads.rs \
  '    fetch_ad_list_from_urls(&DEFAULT_AD_LIST_URLS).await' \
  '    Ok(serde_json::json!({ "version": 1, "ads": [] }))'

echo ">> [2/5] point in-app updater at fork: $REPO_SLUG"
_rep crates/codex-plus-core/src/update.rs 'BigPizzaV3/CodexPlusPlus' "$REPO_SLUG"

echo ">> [3/5] rebrand app name + window title"
_rep apps/codex-plus-manager/src-tauri/tauri.conf.json 'Codex++' "$BRAND"

echo ">> [4/5] rebrand injected + manager UI"
_rep assets/inject/renderer-inject.js 'https://github.com/BigPizzaV3/CodexPlusPlus' "https://github.com/$REPO_SLUG"
_rep assets/inject/renderer-inject.js 'Codex++' "$BRAND"
_rep apps/codex-plus-manager/src/App.tsx 'Codex++' "$BRAND"

echo ">> [5/5] rebrand installers"
_rep scripts/installer/windows/CodexPlusPlus.nsi 'Codex++' "$BRAND"
_rep scripts/installer/windows/CodexPlusPlus.nsi 'CodexPlusPlus-' "$ASSET_PREFIX-"
_rep scripts/installer/macos/package-dmg.sh 'Codex++' "$BRAND"
_rep scripts/installer/macos/package-dmg.sh 'CodexPlusPlus-' "$ASSET_PREFIX-"

echo "OK: yoyo transform applied (REPO_SLUG=$REPO_SLUG BRAND=$BRAND)"
