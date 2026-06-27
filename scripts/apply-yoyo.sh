#!/usr/bin/env bash
# YOYO Plugin — build-time transform for a CodexPlusPlus fork.
# Runs on a CLEAN upstream checkout BEFORE building (never committed), so the
# fork keeps tracking upstream while we strip ads + rebrand each build.
# Every removal is ASSERTED afterwards: if upstream restructures and a removal
# stops matching, the build FAILS LOUDLY instead of silently shipping the ad.
# Usage: REPO_SLUG="you/yoyo-Plugin" BRAND="YOYO Plugin" bash scripts/apply-yoyo.sh
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-${GITHUB_REPOSITORY:-OWNER/yoyo-Plugin}}"
BRAND="${BRAND:-YOYO Plugin}"
ASSET_PREFIX="${ASSET_PREFIX:-YOYOPlugin}"
APP=apps/codex-plus-manager/src/App.tsx
UPD=crates/codex-plus-core/src/update.rs

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
_gone() { ! grep -qF "$2" "$1" || { echo "REMOVAL FAILED in $1 (still present): $2" >&2; exit 7; }; }

echo ">> [1/9] disable in-app ads (推荐内容)"
_rep crates/codex-plus-core/src/ads.rs \
  '    fetch_ad_list_from_urls(&DEFAULT_AD_LIST_URLS).await' \
  '    Ok(serde_json::json!({ "version": 1, "ads": [] }))'

echo ">> [2/9] point ALL CodexPlusPlus repo links at fork: $REPO_SLUG (keep ScriptMarket)"
grep -rlIF 'BigPizzaV3/CodexPlusPlus' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      SLUG="$REPO_SLUG" perl -0777 -i -pe 's{BigPizzaV3/CodexPlusPlus(?!ScriptMarket)}{$ENV{SLUG}}g' "$f"
    done
_gone "$UPD" 'BigPizzaV3/CodexPlusPlus'

echo ">> [3/9] make in-app updater accept rebranded (YOYO) asset filenames"
_rep "$UPD" \
'    name.contains("codex")
        && name.contains("plus")
        && (name.ends_with(".msi")' \
'    (name.ends_with(".msi")'
_rep "$UPD" \
'    name.contains("codex") && name.contains("plus") && name.ends_with(".dmg")' \
'    name.ends_with(".dmg")'
_gone "$UPD" 'name.contains("codex")'

echo ">> [4/9] rebrand installer asset filenames"
_rep scripts/installer/windows/CodexPlusPlus.nsi 'CodexPlusPlus-' "$ASSET_PREFIX-"
_rep scripts/installer/macos/package-dmg.sh 'CodexPlusPlus-' "$ASSET_PREFIX-"

echo ">> [5/9] remove manager '推荐内容' nav entry"
grep -qF 'label: "推荐内容"' "$APP" || { echo "ANCHOR MISSING: 推荐内容 nav" >&2; exit 5; }
perl -0777 -i -pe 's/\n[ \t]*\{ id: "recommendations",[^}]*\},//g' "$APP"
_gone "$APP" 'label: "推荐内容"'

echo ">> [6/9] remove manager Overview '官方中转站' (JOJO) ad card"
grep -qF 'jojocode-overview' "$APP" || { echo "ANCHOR MISSING: jojocode-overview" >&2; exit 5; }
perl -0777 -i -pe 's{\s*<Panel className="jojocode-overview">.*?</Panel>}{}s' "$APP"
_gone "$APP" 'jojocode-overview'

echo ">> [7/9] remove About 'Discord' + 'Telegram' community buttons"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*discord\.gg[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*t\.me/[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
_gone "$APP" 'discord.gg'
_gone "$APP" 't.me/'

echo ">> [8/9] brand badge: C++ -> YOYO (inline font-size so it fits)"
_rep "$APP" '<div className="brand-mark">C++</div>' '<div className="brand-mark" style={{ fontSize: "11px", letterSpacing: "-0.3px" }}>YOYO</div>'

echo ">> [9/9] global rebrand: every visible 'Codex++' -> $BRAND"
grep -rlIF 'Codex++' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      TO="$BRAND" perl -0777 -i -pe 's/\QCodex++\E/$ENV{TO}/g' "$f"
    done

echo "OK: YOYO transform applied (REPO_SLUG=$REPO_SLUG BRAND=$BRAND)"
