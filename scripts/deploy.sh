#!/usr/bin/env bash
# CD-1a（2026-08-23）：bt3 伺服器端部署腳本。
# 用法（在伺服器上以 root 執行）：bash scripts/deploy.sh [git-ref]
#   git-ref 省略時＝origin/main。首次執行前提：/etc/chilllove/env 已存在
#   （SECRET_KEY_BASE／CHILLLOVE_DATABASE_PASSWORD 等，見 docs/specs/120）。
# 設計：冪等——重複執行安全；每步失敗即停（set -e）；結尾 /up 健康檢查，
#   失敗時保留舊進程不 rollout（puma 未重啟成功 systemd 會自動 Restart=always 拉舊碼）。
set -euo pipefail

APP_DIR=/www/wwwroot/chilllove/app
REF="${1:-origin/main}"
export RBENV_ROOT=/opt/rbenv
export PATH="/opt/rbenv/shims:/opt/rbenv/bin:$PATH"

echo "==> [1/7] 取碼：$REF"
cd "$APP_DIR"
sudo -u chilllove git fetch origin --prune
sudo -u chilllove git checkout -q --detach "$REF"
echo "    HEAD=$(git rev-parse --short HEAD)"

echo "==> [2/7] Ruby 依賴"
sudo -u chilllove -H env PATH="$PATH" bundle config set --local deployment true
sudo -u chilllove -H env PATH="$PATH" bundle config set --local without "development test"
sudo -u chilllove -H env PATH="$PATH" bundle install --quiet

echo "==> [3/7] JS 依賴＋前端建置"
sudo -u chilllove -H env PATH="$PATH" pnpm install --frozen-lockfile --silent
set -a; . /etc/chilllove/env; set +a
sudo -u chilllove -H env PATH="$PATH" SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  CHILLLOVE_DATABASE_PASSWORD="$CHILLLOVE_DATABASE_PASSWORD" RAILS_ENV=production \
  bundle exec rails assets:precompile

echo "==> [4/7] 資料庫 prepare（建庫＋遷移，冪等）"
sudo -u chilllove -H env PATH="$PATH" SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  CHILLLOVE_DATABASE_PASSWORD="$CHILLLOVE_DATABASE_PASSWORD" RAILS_ENV=production \
  bundle exec rails db:prepare

echo "==> [5/7] 同步 systemd／nginx 配置（有變更才動）"
install -m 644 config/deploy/chilllove-puma.service /etc/systemd/system/chilllove-puma.service
install -m 644 config/deploy/nginx-chilllove.conf /etc/nginx/sites-available/chilllove
ln -sf /etc/nginx/sites-available/chilllove /etc/nginx/sites-enabled/chilllove
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl daemon-reload
systemctl reload nginx

echo "==> [6/7] 重啟 puma"
systemctl enable -q chilllove-puma
systemctl restart chilllove-puma

echo "==> [7/7] 健康檢查 /up"
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null http://127.0.0.1/up; then
    echo "    ✅ /up 綠（第 ${i} 次嘗試）"; exit 0
  fi
  sleep 2
done
echo "    ❌ /up 30 次未過——查 journalctl -u chilllove-puma" >&2
exit 1
