#!/usr/bin/env bash
# YOYO Plugin — build-time transform for a CodexPlusPlus fork.
# Runs on a CLEAN upstream checkout BEFORE building (never committed), so the
# fork keeps tracking upstream while we strip ads + rebrand each build.
# Every removal is ASSERTED afterwards: if upstream restructures and a removal
# stops matching, the build FAILS LOUDLY instead of silently shipping the ad.
# Anchors are single-line / whitespace-tolerant so Windows (CRLF) is safe.
# Usage: REPO_SLUG="you/yoyo-Plugin" BRAND="YOYO Plugin" bash scripts/apply-yoyo.sh
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-${GITHUB_REPOSITORY:-OWNER/yoyo-Plugin}}"
BRAND="${BRAND:-YOYO Plugin}"
ASSET_PREFIX="${ASSET_PREFIX:-YOYOPlugin}"
APP=apps/codex-plus-manager/src/App.tsx
UPD=crates/codex-plus-core/src/update.rs
CMD=apps/codex-plus-manager/src-tauri/src/commands.rs

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

echo ">> [1/13] disable in-app ads (推荐内容)"
_rep crates/codex-plus-core/src/ads.rs \
  '    fetch_ad_list_from_urls(&DEFAULT_AD_LIST_URLS).await' \
  '    Ok(serde_json::json!({ "version": 1, "ads": [] }))'

echo ">> [2/13] point ALL CodexPlusPlus repo links at fork: $REPO_SLUG (keep ScriptMarket)"
grep -rlIF 'BigPizzaV3/CodexPlusPlus' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      SLUG="$REPO_SLUG" perl -0777 -i -pe 's{BigPizzaV3/CodexPlusPlus(?!ScriptMarket)}{$ENV{SLUG}}g' "$f"
    done
_gone "$UPD" 'BigPizzaV3/CodexPlusPlus'
# Positive assert: if upstream ever moves orgs/renames the repo, the _gone
# check above would pass vacuously and shipped builds would auto-update from
# the (ad-laden) upstream. The updater MUST point at this fork.
grep -qF "$REPO_SLUG" "$UPD" || { echo "REBRAND FAILED: updater does not point at $REPO_SLUG" >&2; exit 7; }

echo ">> [3/13] make in-app updater accept rebranded (YOYO) asset filenames"
# Pre-assert the anchors exist: if upstream refactors the matching code the
# _gone checks below would pass vacuously and the updater would silently
# reject YOYOPlugin-* assets.
grep -qF 'name.contains("codex")' "$UPD" || { echo "ANCHOR MISSING: updater asset matching (codex)" >&2; exit 5; }
grep -qF 'name.contains("plus")' "$UPD" || { echo "ANCHOR MISSING: updater asset matching (plus)" >&2; exit 5; }
perl -0777 -i -pe 's/\Qname.contains("codex")\E/true/g; s/\Qname.contains("plus")\E/true/g' "$UPD"
_gone "$UPD" 'name.contains("codex")'
_gone "$UPD" 'name.contains("plus")'

echo ">> [4/13] humanize provider test result + send Codex-shaped test request"
# 4a. The upstream test sends a minimal payload ("input" as a plain string,
#     tiny max tokens). Codex-only relays often reject that shape with
#     HTTP 400 even though real usage works. Send what Codex itself sends
#     and drop the token caps (both are optional and are known 400 sources).
REL=crates/codex-plus-core/src/relay_config.rs
# Whitespace-tolerant regexes, NOT multi-line literals: the Windows runner
# may check out with CRLF line endings and a literal LF block would never
# match there (sync verify on Linux would still pass -> only Windows dies).
grep -qF '"input": "hi"' "$REL" || { echo "ANCHOR MISSING: relay test payload (responses)" >&2; exit 5; }
grep -qF '"max_tokens": 16' "$REL" || { echo "ANCHOR MISSING: relay test payload (chat)" >&2; exit 5; }
perl -0777 -i -pe 's/RelayProtocol::Responses => serde_json::json!\(\{\s*"model": model,\s*"input": "hi",\s*"max_output_tokens": 16\s*\}\),/RelayProtocol::Responses => serde_json::json!({\n            "model": model,\n            "input": [\n                { "type": "message", "role": "user", "content": [ { "type": "input_text", "text": "hi" } ] }\n            ],\n            "store": false\n        }),/s' "$REL"
perl -0777 -i -pe 's/RelayProtocol::ChatCompletions => serde_json::json!\(\{\s*"model": model,\s*"messages": \[\s*\{ "role": "user", "content": "hi" \}\s*\],\s*"max_tokens": 16\s*\}\),/RelayProtocol::ChatCompletions => serde_json::json!({\n            "model": model,\n            "messages": [\n                { "role": "user", "content": "hi" }\n            ]\n        }),/s' "$REL"
_gone "$REL" '"input": "hi"'
_gone "$REL" '"max_tokens": 16'
_gone "$REL" '"max_output_tokens": 16'
# 4b. Humanized result message instead of the upstream debug-style text.
grep -qF '发送 hi，HTTP' "$CMD" || { echo "ANCHOR MISSING: provider test message" >&2; exit 5; }
perl -0777 -i -pe 's/message: format!\(\s*"已向[^"]*",\s*result\.http_status\s*\)/message: match result.http_status {
                    s if s < 400 => "测试通过，当前节点连通性正常。".to_string(),
                    s @ (401 | 403) => format!("测试未通过：密钥无效或没有访问权限（HTTP {s}）。请检查 API Key 是否正确。"),
                    404 => "测试未通过：接口地址不存在（HTTP 404）。请检查 Base URL 是否缺少 \/v1 前缀。".to_string(),
                    429 => "节点已连通，但请求被限流或额度不足（HTTP 429）。".to_string(),
                    s if s >= 500 => format!("测试未通过：节点服务器出错（HTTP {s}），可能是临时故障，请稍后重试。"),
                    s => format!("测试未通过：请求被节点拒绝（HTTP {s}）。"),
                }/s' "$CMD"
_gone "$CMD" '发送 hi，HTTP'
grep -qF '测试通过，当前节点连通性正常' "$CMD" || { echo "provider test humanize FAILED" >&2; exit 7; }

echo ">> [5/13] rebrand installer asset filenames + quote UninstallString"
_rep scripts/installer/windows/CodexPlusPlus.nsi 'CodexPlusPlus-' "$ASSET_PREFIX-"
_rep scripts/installer/macos/package-dmg.sh 'CodexPlusPlus-' "$ASSET_PREFIX-"
# The rebrand puts a space in $INSTDIR ("...\Programs\YOYO Plugin"), so the
# registry UninstallString must be quoted or unquoted-path parsing applies.
_rep scripts/installer/windows/CodexPlusPlus.nsi \
  '"UninstallString" "$INSTDIR\uninstall.exe"' \
  '"UninstallString" "$\"$INSTDIR\uninstall.exe$\""'

echo ">> [6/13] remove manager '推荐内容' nav entry"
# Anchor on the entry id, not the label: upstream wrapped labels in t("...")
# for i18n, and may re-wrap again; the id is the stable part.
grep -qF '{ id: "recommendations",' "$APP" || { echo "ANCHOR MISSING: 推荐内容 nav" >&2; exit 5; }
perl -0777 -i -pe 's/\n[ \t]*\{ id: "recommendations",[^}]*\},//g' "$APP"
_gone "$APP" '{ id: "recommendations",'

echo ">> [7/13] remove manager Overview '官方中转站' (JOJO) ad card"
grep -qF 'jojocode-overview' "$APP" || { echo "ANCHOR MISSING: jojocode-overview" >&2; exit 5; }
perl -0777 -i -pe 's{\s*<Panel className="jojocode-overview">.*?</Panel>}{}s' "$APP"
_gone "$APP" 'jojocode-overview'

echo ">> [8/13] remove upstream Discord/Telegram community links (manager + injected menu)"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*discord\.gg[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*t\.me/[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
_gone "$APP" 'discord.gg'
_gone "$APP" 't.me/'
INJ=assets/inject/renderer-inject.js
grep -qF 'data-codex-plus-discord' "$INJ" || { echo "ANCHOR MISSING: injected Discord row" >&2; exit 5; }
grep -qF 'data-codex-plus-telegram' "$INJ" || { echo "ANCHOR MISSING: injected Telegram row" >&2; exit 5; }
# About text links
perl -0777 -i -pe 's!<br>Discord: <a href="https://discord\.gg/[^"]*"[^>]*>[^<]*</a><br>Telegram: <a href="https://t\.me/[^"]*"[^>]*>[^<]*</a>!!' "$INJ"
# Home-tab rows
perl -0777 -i -pe 's!\s*<div class="codex-plus-row">\s*<div><div class="codex-plus-row-title">Discord 社区</div><div class="codex-plus-row-description">[^<]*</div></div>\s*<button type="button" class="codex-plus-action-button" data-codex-plus-discord="true">[^<]*</button>\s*</div>!!s' "$INJ"
perl -0777 -i -pe 's!\s*<div class="codex-plus-row">\s*<div><div class="codex-plus-row-title">Telegram 频道</div><div class="codex-plus-row-description">[^<]*</div></div>\s*<button type="button" class="codex-plus-action-button" data-codex-plus-telegram="true">[^<]*</button>\s*</div>!!s' "$INJ"
# Click handlers (would be dead code, but remove so the _gone checks are real)
perl -0777 -i -pe 's!\s*if \(target\?\.closest\("\[data-codex-plus-discord\]"\)\) \{\s*window\.open\("https://discord\.gg/[^"]*", "_blank"\);\s*return;\s*\}!!s' "$INJ"
perl -0777 -i -pe 's!\s*if \(target\?\.closest\("\[data-codex-plus-telegram\]"\)\) \{\s*window\.open\("https://t\.me/[^"]*", "_blank"\);\s*return;\s*\}!!s' "$INJ"
_gone "$INJ" 'discord.gg'
_gone "$INJ" 't.me/'

echo ">> [9/13] brand badge: C++ -> YOYO (inline font-size so it fits)"
_rep "$APP" '<div className="brand-mark">C++</div>' '<div className="brand-mark" style={{ fontSize: "11px", letterSpacing: "-0.3px" }}>YOYO</div>'

echo ">> [10/13] global rebrand: every visible 'Codex++' -> $BRAND"
grep -rlIF 'Codex++' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      TO="$BRAND" perl -0777 -i -pe 's/\QCodex++\E/$ENV{TO}/g' "$f"
    done
# Positive assert on the most user-visible surface (window title / app name),
# plus a residue sweep: if upstream ever respells the brand, fail loudly
# instead of shipping half-branded installers.
grep -qF "$BRAND" apps/codex-plus-manager/src-tauri/tauri.conf.json || { echo "REBRAND FAILED: tauri.conf.json lacks '$BRAND'" >&2; exit 7; }
LEFT=$(grep -rlIF 'Codex++' apps crates assets scripts 2>/dev/null \
  | grep -vE '/node_modules/|/target/|package-lock\.json|scripts/apply-yoyo\.sh' || true)
[ -z "$LEFT" ] || { echo "REBRAND FAILED: 'Codex++' still present in: $LEFT" >&2; exit 7; }

echo ">> [11/13] disable injected-menu remote ads (fetched in-browser, bypasses ads.rs)"
# Pre-assert: _rep's "TO already present" tolerance is vacuously satisfied by
# the unrelated `let codexPlusAds = [];` declaration, so without this check an
# upstream rename of directFetchCodexPlusAds would silently re-ship the ads.
grep -qF 'codexPlusAds = normalizeCodexPlusAds(await directFetchCodexPlusAds());' "$INJ" || { echo "ANCHOR MISSING: injected ad fetch call" >&2; exit 5; }
_rep "$INJ" \
  'codexPlusAds = normalizeCodexPlusAds(await directFetchCodexPlusAds());' \
  'codexPlusAds = [];'
_gone "$INJ" 'await directFetchCodexPlusAds()'

echo ">> [12/13] remove injected-menu '推荐内容' tab"
grep -qF 'data-codex-plus-tab="sponsor"' "$INJ" || { echo "ANCHOR MISSING: injected sponsor tab" >&2; exit 5; }
perl -0777 -i -pe 's!\s*<button type="button" class="codex-plus-tab-button" data-codex-plus-tab="sponsor"[^>]*>[^<]*</button>!!' "$INJ"
_gone "$INJ" 'data-codex-plus-tab="sponsor"'

echo ">> [13/13] remove injected-menu '请作者喝咖啡' donation tab"
grep -qF 'data-codex-plus-tab="support"' "$INJ" || { echo "ANCHOR MISSING: injected support tab" >&2; exit 5; }
perl -0777 -i -pe 's!\s*<button type="button" class="codex-plus-tab-button" data-codex-plus-tab="support"[^>]*>[^<]*</button>!!' "$INJ"
_gone "$INJ" 'data-codex-plus-tab="support"'

echo "OK: YOYO transform applied (REPO_SLUG=$REPO_SLUG BRAND=$BRAND)"
