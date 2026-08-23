#!/usr/bin/env bash
# CD-1a（2026-08-23）：bt3 伺服器端部署腳本。
# 用法（在伺服器上以 root 執行）：bash scripts/deploy.sh [git-ref]
#   git-ref 省略時＝origin/main。首次執行前提：/etc/chilllove/env 已存在
#   （SECRET_KEY_BASE／CHILLLOVE_DATABASE_PASSWORD 等，見 docs/specs/120）。
# 設計：冪等——重複執行安全；每步失敗即停（set -e）；結尾 /up 健康檢查，
#   失敗時保留舊進程不 rollout（puma 未重啟成功 systemd 會自動 Restart=always 拉舊碼）。
set -euo pipefail

APP_DIR=/www/wwwroot/chilllove/app
ENV_FILE=/etc/chilllove/env
REF="${1:-origin/main}"
export RBENV_ROOT=/opt/rbenv
export PATH="/opt/rbenv/shims:/opt/rbenv/bin:$PATH"

# 以 app 使用者執行一道命令，讓**子行程自己讀** $ENV_FILE。
#
# 🔴 不用 `env VAR=$VAR ...` 逐個轉交：①漏一個就炸在部署中途
#    （CHILLLOVE_BASE_HOST 漏轉交害 assets:precompile 掛在 KeyError，實測 2026-08-23）
#    ②轉交等於把秘密寫進 argv，`ps aux` 全機可見。
# 🔴 不用 `sudo -E`：本機 sudoers 明文拒絕（實測訊息
#    "preserving the entire environment is not supported, '-E' is ignored"），
#    會靜默降級成沒帶環境——比報錯更糟。
# ⇒ `env -i` 清空後只給 PATH/HOME/RBENV_ROOT，其餘由子行程 source env 檔取得
#   （檔案 0640 root:chilllove，app 使用者靠群組讀得到）。
run_as_app() {
  sudo -u chilllove -H env -i \
    PATH="$PATH" HOME=/home/chilllove RBENV_ROOT="$RBENV_ROOT" \
    bash -c 'cd "$0"; set -a; . "$1"; set +a; shift 2; exec "$@"' \
    "$APP_DIR" "$ENV_FILE" -- "$@"
}

echo "==> [1/7] 取碼：$REF"
cd "$APP_DIR"
sudo -u chilllove git fetch origin --prune
sudo -u chilllove git checkout -q --detach "$REF"
echo "    HEAD=$(git rev-parse --short HEAD)"

echo "==> [2/7] Ruby 依賴"
run_as_app bundle config set --local deployment true
run_as_app bundle config set --local without "development test"
run_as_app bundle install --quiet

echo "==> [3/7] JS 依賴＋前端建置"
run_as_app pnpm install --frozen-lockfile --silent
run_as_app bundle exec rails assets:precompile

echo "==> [4/7] 資料庫 prepare（建庫＋遷移，冪等）"
run_as_app bundle exec rails db:prepare

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
