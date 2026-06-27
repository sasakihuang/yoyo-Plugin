#!/usr/bin/env bash
# YOYO Plugin — build-time transform for a CodexPlusPlus fork.
# Runs on a CLEAN upstream checkout BEFORE building (never committed), so the
# fork keeps tracking upstream while we strip ads + rebrand each build.
#   1. Disable in-app ads (推荐内容) at the data source.
#   2. Point the in-app updater at YOUR fork's releases.
#   3. Remove the manager's "推荐内容" page + the Overview "官方中转站" (JOJO) ad.
#   4. Rebrand every visible "Codex++" -> "YOYO Plugin" (+ the C++ badge -> YO).
# Internal ids (codex-plus-plus binaries, CodexPlusPlus provider, codex-plus-*
# CSS) use different spellings and are left untouched. Any missing anchor EXITS
# NON-ZERO so the build fails loudly instead of shipping ads/branding.
# Usage: REPO_SLUG="you/yoyo-Plugin" BRAND="YOYO Plugin" bash scripts/apply-yoyo.sh
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-${GITHUB_REPOSITORY:-OWNER/yoyo-Plugin}}"
BRAND="${BRAND:-YOYO Plugin}"
ASSET_PREFIX="${ASSET_PREFIX:-YOYOPlugin}"
APP=apps/codex-plus-manager/src/App.tsx

ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

_rep() {  # <file> <FROM> <TO> : literal, global, anchor-checked
  local f="$1"
  [ -f "$f" ] || { echo "MISSING FILE: $f" >&2; exit 2; }
  FROM="$2" TO="$3" FILE="$f" perl -0777 -i -pe '
    BEGIN { $from=$ENV{FROM}; $to=$ENV{TO}; $file=$ENV{FILE}; }
    if (index($_,$from)>=0) { s/\Q$from\E/$to/g; }
    elsif (index($_,$to)>=0) { }
    else { die "ANCHOR MISSING in $file: $from\n"; }
  ' "$f"
}
_require() { grep -qF "$2" "$1" || { echo "ANCHOR MISSING in $1: $2" >&2; exit 5; }; }

echo ">> [1/7] disable in-app ads (推荐内容)"
_rep crates/codex-plus-core/src/ads.rs \
  '    fetch_ad_list_from_urls(&DEFAULT_AD_LIST_URLS).await' \
  '    Ok(serde_json::json!({ "version": 1, "ads": [] }))'

echo ">> [2/7] point in-app updater at fork: $REPO_SLUG"
_rep crates/codex-plus-core/src/update.rs 'BigPizzaV3/CodexPlusPlus' "$REPO_SLUG"
_rep assets/inject/renderer-inject.js 'https://github.com/BigPizzaV3/CodexPlusPlus' "https://github.com/$REPO_SLUG"

echo ">> [3/7] rebrand installer asset filenames"
_rep scripts/installer/windows/CodexPlusPlus.nsi 'CodexPlusPlus-' "$ASSET_PREFIX-"
_rep scripts/installer/macos/package-dmg.sh 'CodexPlusPlus-' "$ASSET_PREFIX-"

echo ">> [4/7] remove manager '推荐内容' nav entry"
_require "$APP" 'label: "推荐内容"'
perl -0777 -i -pe 's/\Q  { id: "recommendations", label: "推荐内容", icon: ExternalLink },\E\n//' "$APP"

echo ">> [5/7] remove manager Overview '官方中转站' (JOJO) ad card"
_require "$APP" 'jojocode-overview'
perl -0777 -i -pe 's{\s*<Panel className="jojocode-overview">.*?</Panel>}{}s' "$APP"

echo ">> [6/7] replace 'C++' brand badge -> YO"
_rep "$APP" '<div className="brand-mark">C++</div>' '<div className="brand-mark">YO</div>'

echo ">> [7/7] global rebrand: every visible 'Codex++' -> $BRAND"
grep -rlIF 'Codex++' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      TO="$BRAND" perl -0777 -i -pe 's/\QCodex++\E/$ENV{TO}/g' "$f"
    done

echo "OK: YOYO transform applied (REPO_SLUG=$REPO_SLUG BRAND=$BRAND)"
