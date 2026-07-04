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

echo ">> [3/13] make in-app updater accept rebranded (YOYO) asset filenames"
perl -0777 -i -pe 's/\Qname.contains("codex")\E/true/g; s/\Qname.contains("plus")\E/true/g' "$UPD"
_gone "$UPD" 'name.contains("codex")'
_gone "$UPD" 'name.contains("plus")'

echo ">> [4/13] humanize provider test result + send Codex-shaped test request"
# 4a. The upstream test sends a minimal payload ("input" as a plain string,
#     tiny max tokens). Codex-only relays often reject that shape with
#     HTTP 400 even though real usage works. Send what Codex itself sends
#     and drop the token caps (both are optional and are known 400 sources).
REL=crates/codex-plus-core/src/relay_config.rs
_rep "$REL" '        RelayProtocol::Responses => serde_json::json!({
            "model": model,
            "input": "hi",
            "max_output_tokens": 16
        }),' '        RelayProtocol::Responses => serde_json::json!({
            "model": model,
            "input": [
                { "type": "message", "role": "user", "content": [ { "type": "input_text", "text": "hi" } ] }
            ],
            "store": false
        }),'
_rep "$REL" '        RelayProtocol::ChatCompletions => serde_json::json!({
            "model": model,
            "messages": [
                { "role": "user", "content": "hi" }
            ],
            "max_tokens": 16
        }),' '        RelayProtocol::ChatCompletions => serde_json::json!({
            "model": model,
            "messages": [
                { "role": "user", "content": "hi" }
            ]
        }),'
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

echo ">> [5/13] rebrand installer asset filenames"
_rep scripts/installer/windows/CodexPlusPlus.nsi 'CodexPlusPlus-' "$ASSET_PREFIX-"
_rep scripts/installer/macos/package-dmg.sh 'CodexPlusPlus-' "$ASSET_PREFIX-"

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

echo ">> [8/13] remove About 'Discord' + 'Telegram' community buttons"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*discord\.gg[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*t\.me/[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
_gone "$APP" 'discord.gg'
_gone "$APP" 't.me/'

echo ">> [9/13] brand badge: C++ -> YOYO (inline font-size so it fits)"
_rep "$APP" '<div className="brand-mark">C++</div>' '<div className="brand-mark" style={{ fontSize: "11px", letterSpacing: "-0.3px" }}>YOYO</div>'

echo ">> [10/13] global rebrand: every visible 'Codex++' -> $BRAND"
grep -rlIF 'Codex++' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      TO="$BRAND" perl -0777 -i -pe 's/\QCodex++\E/$ENV{TO}/g' "$f"
    done

INJ=assets/inject/renderer-inject.js

echo ">> [11/13] disable injected-menu remote ads (fetched in-browser, bypasses ads.rs)"
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
