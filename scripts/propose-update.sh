#!/usr/bin/env bash
# Propose an upstream update for owner approval (schedule mode of yoyo-sync).
# Opens/updates an "upstream-update" issue containing:
#   1. version bump + commit list,
#   2. a promo/ads scan of the upstream diff (引流检查),
#   3. an apply-yoyo.sh precheck against the merged tree,
#   4. old-vs-new screenshots of every manager page that changed (best-effort).
# GitHub emails the issue to the owner; replying 更新/approve triggers the build.
# Requires: upstream remote fetched, git identity configured, GH_TOKEN, REPO.
set -euo pipefail

UPSTREAM_REF="${UPSTREAM_REF:-upstream/main}"
REPO="${REPO:?}"
WORK="${RUNNER_TEMP:-/tmp}/yoyo-propose"
rm -rf "$WORK" && mkdir -p "$WORK"

UP=$(git rev-parse "$UPSTREAM_REF")
COUNT=$(git rev-list --count "HEAD..$UPSTREAM_REF")
if [ "$COUNT" = "0" ]; then
  echo "No new upstream commits."
  # Keepalive: GitHub disables cron schedules after 60 days without commits.
  AGE_DAYS=$(( ( $(date +%s) - $(git log -1 --format=%ct) ) / 86400 ))
  if [ "$AGE_DAYS" -ge 50 ]; then
    git commit --allow-empty -m "yoyo: keepalive (quiet for ${AGE_DAYS} days)"
    git push origin HEAD
  fi
  exit 0
fi

MARK="<!-- upstream-sha: $UP -->"
EXISTING=$(gh issue list --repo "$REPO" --label upstream-update --state open --json number,body --limit 1)
NUM=$(printf '%s' "$EXISTING" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(d[0]?d[0].number:"")')
OLD_BODY=$(printf '%s' "$EXISTING" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(d[0]?d[0].body:"")')
if [ -n "$NUM" ] && printf '%s' "$OLD_BODY" | grep -qF "$MARK"; then
  echo "Already notified for $UP (issue #$NUM)."
  exit 0
fi

CUR_V=$(awk '/^\[workspace.package\]/{f=1} f&&/^version/{gsub(/[^0-9.]/,"",$0);print;exit}' Cargo.toml)
UP_V=$(git show "$UPSTREAM_REF:Cargo.toml" | awk '/^\[workspace.package\]/{f=1} f&&/^version/{gsub(/[^0-9.]/,"",$0);print;exit}')
BASE=$(git merge-base HEAD "$UPSTREAM_REF")

# ---------- 1. promo / traffic-driving scan over ADDED lines ----------
# Track the current file from diff headers so hits carry their location.
git diff --unified=0 "HEAD..$UPSTREAM_REF" -- . ':!package-lock.json' > "$WORK/up.diff" || true
PROMO_RE='discord\.gg|t\.me/|qq\.(com|cn)|jq\.qq\.com|weixin|wechat|公众号|微信群|QQ群|二维码|收款|赞助|打赏|喝咖啡|请作者|sponsor|donat|bilibili|b23\.tv|douyin|抖音|快手|小红书|xiaohongshu|推广|广告|邀请码|返利|优惠码|aff=|utm_|推荐内容|官方中转|\bStar\b|点个 ?[Ss]tar|星标|支持作者'
awk -v re="$PROMO_RE" '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^\+/ && $0 !~ /^\+\+\+/ {
    line = substr($0, 2)
    if (line ~ re) {
      gsub(/[[:space:]]+/, " ", line)
      printf "- `%s`: %s\n", file, substr(line, 1, 160)
    }
  }
' "$WORK/up.diff" | head -20 > "$WORK/promo_hits.md" || true

# New external domains introduced by the diff (not present in the current tree)
grep '^+' "$WORK/up.diff" | grep -v '^+++' \
  | grep -oE 'https?://[a-zA-Z0-9.-]+' | sed 's#https\?://##' | sort -u > "$WORK/domains_new.txt" || true
: > "$WORK/domains_report.txt"
while IFS= read -r d; do
  [ -n "$d" ] || continue
  if ! grep -rqF "$d" apps crates assets scripts --include='*.rs' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.json' 2>/dev/null; then
    echo "- $d" >> "$WORK/domains_report.txt"
  fi
done < "$WORK/domains_new.txt"

# Newly added image/media assets (potential ad creatives)
git diff --name-status "HEAD..$UPSTREAM_REF" | awk '$1=="A" && $2 ~ /\.(png|jpe?g|svg|gif|webp|ico)$/ { print "- `" $2 "`" }' | head -15 > "$WORK/new_assets.md" || true

# ---------- 2. apply-yoyo.sh precheck on the merged tree ----------
PRECHECK_STATUS="✅ 通过"
git worktree add --detach "$WORK/merged" HEAD >/dev/null
(
  cd "$WORK/merged"
  git -c user.name=yoyo-bot -c user.email=yoyo-bot@users.noreply.github.com \
    merge -X ours --no-edit "$UP" >/dev/null
) || PRECHECK_STATUS="❌ 合并冲突（需人工处理）"
if [ "$PRECHECK_STATUS" = "✅ 通过" ]; then
  if ! (cd "$WORK/merged" && REPO_SLUG="$REPO" BRAND="${BRAND:-YOYO Plugin}" GITHUB_WORKSPACE="$WORK/merged" \
        bash scripts/apply-yoyo.sh > "$WORK/precheck.log" 2>&1); then
    PRECHECK_STATUS="❌ 失败：$(tail -2 "$WORK/precheck.log" | head -1 | cut -c1-200)（确认前需先修 apply-yoyo.sh）"
  fi
fi

# ---------- 3. old-vs-new page screenshots (best effort, never blocks) ----------
# Screenshots are MANDATORY: if they cannot be produced, this run fails
# loudly (workflow failure alert) and the next scheduled run retries — an
# approval email without screenshots is never sent. Sole exception: the
# patch precheck failed, so the new tree cannot be built at all; the email
# then says so explicitly instead of carrying screenshots.
if [ "$PRECHECK_STATUS" = "✅ 通过" ]; then
  cd "$WORK"
  mkdir -p tool && cd tool
  npm init -y >/dev/null
  npm install --no-audit --no-fund playwright pixelmatch@5 pngjs >/dev/null
  npx playwright install --with-deps chromium >/dev/null
  cd "$WORK"

  git worktree add --detach "$WORK/current" HEAD >/dev/null
  (cd "$WORK/current" && REPO_SLUG="$REPO" BRAND="${BRAND:-YOYO Plugin}" GITHUB_WORKSPACE="$WORK/current" bash scripts/apply-yoyo.sh >/dev/null)
  for TREE in current merged; do
    (cd "$WORK/$TREE/apps/codex-plus-manager" && npm install --package-lock=false --no-audit --no-fund >/dev/null 2>&1 && npm run vite:build >/dev/null)
  done
  cd "$WORK/tool"
  node "$GITHUB_WORKSPACE/scripts/ui-preview.mjs" "$WORK/current/apps/codex-plus-manager/dist" "$WORK/shots-old"
  node "$GITHUB_WORKSPACE/scripts/ui-preview.mjs" "$WORK/merged/apps/codex-plus-manager/dist" "$WORK/shots-new"
  node "$GITHUB_WORKSPACE/scripts/ui-compare.mjs" "$WORK/shots-old" "$WORK/shots-new" "$WORK/uidiff.json"
  cd "$WORK"

  # Publish images on an orphan branch; issues/emails render the raw URLs.
  # When nothing changed, still publish one new-version sample page as the
  # mandatory visual proof that the comparison actually ran.
  PREV="ui-preview/${UP:0:12}"
  git worktree add --detach "$WORK/preview" HEAD >/dev/null
  (
    cd "$WORK/preview"
    git checkout --orphan ui-preview-tmp >/dev/null 2>&1
    git rm -rfq . >/dev/null 2>&1 || true
    mkdir -p "$PREV"
    W="$WORK" P="$PREV" node -e '
      const fs = require("fs"), path = require("path");
      const diff = JSON.parse(fs.readFileSync(process.env.W + "/uidiff.json", "utf8"));
      const out = [];
      for (const r of diff) {
        if (r.status === "same") continue;
        const slug = Buffer.from(r.label).toString("hex").slice(0, 16);
        const entry = { ...r, slug };
        if (r.oldFile) { fs.copyFileSync(r.oldFile, path.join(process.env.P, slug + "-old.png")); entry.old = slug + "-old.png"; }
        if (r.newFile) { fs.copyFileSync(r.newFile, path.join(process.env.P, slug + "-new.png")); entry.new = slug + "-new.png"; }
        out.push(entry);
      }
      if (out.length === 0) {
        const manifest = JSON.parse(fs.readFileSync(process.env.W + "/shots-new/pages.json", "utf8"));
        const first = manifest.find((m) => m.file);
        if (!first) { console.error("no captured pages to sample"); process.exit(1); }
        fs.copyFileSync(path.join(process.env.W, "shots-new", first.file), path.join(process.env.P, "sample-new.png"));
        out.push({ label: first.label, status: "sample", new: "sample-new.png", total: manifest.length });
      }
      fs.writeFileSync(process.env.W + "/changed.json", JSON.stringify(out));
    '
    git add "$PREV"
    git commit -qm "ui preview for ${UP:0:12}"
    git push -f origin ui-preview-tmp:ui-preview
  )
  RAWBASE="https://raw.githubusercontent.com/${REPO}/ui-preview/${PREV}"
  SHOTS_SECTION=$(W="$WORK" RAWBASE="$RAWBASE" node -e '
    const fs = require("fs");
    const changed = JSON.parse(fs.readFileSync(process.env.W + "/changed.json", "utf8"));
    const base = process.env.RAWBASE;
    const lines = [];
    if (changed.length === 1 && changed[0].status === "sample") {
      const s = changed[0];
      lines.push(`界面逐页对比：全部 ${s.total} 页与当前版本逐像素一致，**没有可见变化**（仅代码内部改动）。`);
      lines.push(`新版「${s.label}」抽样截图（核验凭证）：`);
      lines.push(`![${s.label} 新版抽样](${base}/${s.new})`);
    } else {
      for (const r of changed) {
        const tag = r.status === "new" ? "新增页面" : r.status === "removed" ? "页面移除" : `有变化（差异 ${r.diffPct}%）`;
        lines.push(`#### ${r.label} — ${tag}`);
        if (r.old) lines.push(`旧版：\n![${r.label} 旧版](${base}/${r.old})`);
        if (r.new) lines.push(`新版：\n![${r.label} 新版](${base}/${r.new})`);
      }
    }
    console.log(lines.join("\n"));
  ')
  [ -n "$SHOTS_SECTION" ] || { echo "screenshot section came out empty — refusing to send an incomplete proposal" >&2; exit 9; }
else
  SHOTS_SECTION="❌ 去广告补丁预检失败，新版本当前无法构建，因此无法生成界面截图。请先修复 apply-yoyo.sh 后再确认（此时回复「更新」构建也会失败）。"
fi

# ---------- 4. compose + create/update the issue ----------
{
  echo "$MARK"
  echo "上游有 ${COUNT} 个新提交（当前 v${CUR_V} → 上游 v${UP_V}）。"
  echo
  echo "### 更新内容"
  git log --no-merges --pretty='- %s' "HEAD..$UPSTREAM_REF" | head -50
  [ "$(git log --no-merges --oneline "HEAD..$UPSTREAM_REF" | wc -l)" -gt 50 ] && echo "- …（更多省略）"
  echo
  echo "完整对比：https://github.com/BigPizzaV3/CodexPlusPlus/compare/${BASE:0:12}...${UP:0:12}"
  echo
  echo "### 引流/广告自动检查"
  if [ -s "$WORK/promo_hits.md" ]; then
    echo "⚠️ 新增代码中发现以下可疑内容（请重点审核）："
    cat "$WORK/promo_hits.md"
  else
    echo "✅ 新增代码中未发现广告/引流特征词。"
  fi
  if [ -s "$WORK/domains_report.txt" ]; then
    echo
    echo "本次新引入的外部域名："
    cat "$WORK/domains_report.txt"
  fi
  if [ -s "$WORK/new_assets.md" ]; then
    echo
    echo "新增图片资源（可能是广告素材，见下方截图核对）："
    cat "$WORK/new_assets.md"
  fi
  echo
  echo "### 去广告补丁预检"
  echo "apply-yoyo.sh 在合并副本上试运行：${PRECHECK_STATUS}"
  echo
  echo "### 界面变化截图（旧版 vs 新版）"
  echo "$SHOTS_SECTION"
  echo
  echo "### 如何确认更新"
  echo "**直接回复这封邮件（或在本 issue 评论）「更新」即可开始构建发布。**"
  echo "也可以回复 approve / 同意 / 构建。不回复则一直保持当前版本。"
} > "$WORK/body.md"

gh label create upstream-update --repo "$REPO" -c '#0e8a16' -d 'Upstream update pending approval' 2>/dev/null || true
TITLE="上游更新待确认：v${CUR_V} → v${UP_V}（${COUNT} 个新提交）"
if [ -n "$NUM" ]; then
  gh issue edit "$NUM" --repo "$REPO" --title "$TITLE" --body-file "$WORK/body.md"
  gh issue comment "$NUM" --repo "$REPO" --body "上游又有新提交，简介与截图已更新（现在共 ${COUNT} 个新提交，最新版本 v${UP_V}）。回复「更新」即可构建发布。"
else
  gh issue create --repo "$REPO" --label upstream-update --title "$TITLE" --body-file "$WORK/body.md"
fi
echo "Proposal issue created/updated; waiting for approval."
