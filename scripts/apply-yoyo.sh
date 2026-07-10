#!/usr/bin/env bash
# YOYO Plugin — build-time patch applied to a clean checkout BEFORE building.
# Applied ephemerally (never committed) so the repo keeps tracking its base.
# Every patch is ASSERTED afterwards: if the base restructures and a step stops
# matching, the build FAILS LOUDLY instead of shipping an inconsistent app.
# Anchors are single-line / whitespace-tolerant so Windows (CRLF) is safe.
# Usage: REPO_SLUG="you/yoyo-Plugin" BRAND="YOYO Plugin" bash scripts/apply-yoyo.sh
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-${GITHUB_REPOSITORY:-OWNER/yoyo-Plugin}}"
BRAND="${BRAND:-YOYO Plugin}"
ASSET_PREFIX="${ASSET_PREFIX:-YOYOPlugin}"
APP=apps/codex-plus-manager/src/App.tsx
UPD=crates/codex-plus-core/src/update.rs
CMD=apps/codex-plus-manager/src-tauri/src/commands.rs
INJ=assets/inject/renderer-inject.js

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

echo ">> [1/10] patch: core service defaults"
_rep crates/codex-plus-core/src/ads.rs \
  '    fetch_ad_list_from_urls(&DEFAULT_AD_LIST_URLS).await' \
  '    Ok(serde_json::json!({ "version": 1, "ads": [] }))'

echo ">> [2/10] patch: repo links -> $REPO_SLUG"
grep -rlIF 'BigPizzaV3/CodexPlusPlus' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      SLUG="$REPO_SLUG" perl -0777 -i -pe 's{BigPizzaV3/CodexPlusPlus(?!ScriptMarket)}{$ENV{SLUG}}g' "$f"
    done
_gone "$UPD" 'BigPizzaV3/CodexPlusPlus'

echo ">> [3/10] patch: updater asset matching"
perl -0777 -i -pe 's/\Qname.contains("codex")\E/true/g; s/\Qname.contains("plus")\E/true/g' "$UPD"
_gone "$UPD" 'name.contains("codex")'
_gone "$UPD" 'name.contains("plus")'

echo ">> [4/10] patch: provider test message"
grep -qF '发送 hi，HTTP' "$CMD" || { echo "ANCHOR MISSING: provider test message" >&2; exit 5; }
perl -0777 -i -pe 's/message: format!\(\s*"已向[^"]*",\s*result\.http_status\s*\)/message: if result.http_status < 400 { format!("连接正常（HTTP {}）", result.http_status) } else { format!("连接失败（HTTP {}）", result.http_status) }/s' "$CMD"
_gone "$CMD" '发送 hi，HTTP'
grep -qF 'message: if result.http_status < 400' "$CMD" || { echo "provider test simplify FAILED" >&2; exit 7; }

echo ">> [5/10] patch: installer filenames"
_rep scripts/installer/windows/CodexPlusPlus.nsi 'CodexPlusPlus-' "$ASSET_PREFIX-"
_rep scripts/installer/macos/package-dmg.sh 'CodexPlusPlus-' "$ASSET_PREFIX-"

echo ">> [6/10] patch: nav entries"
grep -qF '{ id: "recommendations",' "$APP" || { echo "ANCHOR MISSING: recommendations nav" >&2; exit 5; }
perl -0777 -i -pe 's/\n[ \t]*\{ id: "recommendations",[^}]*\},//g' "$APP"
_gone "$APP" '{ id: "recommendations",'

echo ">> [7/10] patch: overview cards"
grep -qF 'jojocode-overview' "$APP" || { echo "ANCHOR MISSING: jojocode-overview" >&2; exit 5; }
perl -0777 -i -pe 's{\s*<Panel className="jojocode-overview">.*?</Panel>}{}s' "$APP"
_gone "$APP" 'jojocode-overview'

echo ">> [8/10] patch: about panel + links"
# injected menu: drop rows by stable data-attr (text-agnostic)
for KEY in discord telegram issue; do
  perl -0777 -i -pe 's{\s*<div class="codex-plus-row">\s*<div><div class="codex-plus-row-title">[^<]*</div><div class="codex-plus-row-description">[^<]*</div></div>\s*<button[^>]*data-codex-plus-'"$KEY"'[^>]*>[^<]*</button>\s*</div>}{}sg' "$INJ"
done
perl -0777 -i -pe 's{<br>Discord: <a[^>]*>[^<]*</a><br>Telegram: <a[^>]*>[^<]*</a>}{}sg' "$INJ"
_gone "$INJ" 'Discord 社区'
_gone "$INJ" 'Telegram 频道'
# manager About: drop external-link buttons (keep project home -> fork)
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*openExternalUrl\("https://github\.com/[^"]*/issues"\)[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*discord\.gg[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*t\.me/[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
_gone "$APP" 'discord.gg'
_gone "$APP" 't.me/'
_gone "$APP" '/issues"'

echo ">> [9/10] patch: brand badge"
_rep "$APP" '<div className="brand-mark">C++</div>' '<div className="brand-mark" style={{ fontSize: "11px", letterSpacing: "-0.3px" }}>YOYO</div>'

echo ">> [10/10] patch: brand strings -> $BRAND"
grep -rlIF 'Codex++' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      TO="$BRAND" perl -0777 -i -pe 's/\QCodex++\E/$ENV{TO}/g' "$f"
    done

echo "OK: build patch applied (REPO_SLUG=$REPO_SLUG BRAND=$BRAND)"
