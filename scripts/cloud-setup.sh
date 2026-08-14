#!/usr/bin/env bash
# CHILL LOVE — Claude Code web 雲端環境 setup script
#
# 用法：在 claude.ai/code 的環境設定（Environment settings）的 setup script 欄填：
#   bash scripts/cloud-setup.sh
# 官方約束：上限 5 分鐘，成功後會快取供後續 session 復用（code.claude.com/docs/en/cloud-environments）。
#
# 設計為 best-effort：任何一段失敗只警告、不讓 session 建立失敗（官方文檔：setup 超時/失敗
# 會擋 session 建立，所以這裡刻意不用 set -e）。缺的部分 session 內可自行補跑。
set -uo pipefail

log() { echo "[cloud-setup] $*"; }

# 三路並行（官方最佳實踐：獨立安裝並行、控制在 5 分鐘內）
bundle install --jobs 4 >/tmp/setup-bundle.log 2>&1 &
BUNDLE_PID=$!

( corepack enable && pnpm install --frozen-lockfile ) >/tmp/setup-pnpm.log 2>&1 &
PNPM_PID=$!

( docker pull mysql:8.4 && \
  docker run -d --name chilllove-mysql -e MYSQL_ALLOW_EMPTY_PASSWORD=1 -p 3306:3306 mysql:8.4 ) \
  >/tmp/setup-mysql.log 2>&1 &
MYSQL_PID=$!

wait $BUNDLE_PID && log "bundle install OK" || log "⚠ bundle install 失敗（見 /tmp/setup-bundle.log）"
wait $PNPM_PID   && log "pnpm install OK"   || log "⚠ pnpm install 失敗（見 /tmp/setup-pnpm.log）"
wait $MYSQL_PID  && log "mysql 容器已啟動"  || log "⚠ docker mysql 失敗（見 /tmp/setup-mysql.log）"

# 等 MySQL ready（最多 60 秒），成功才建測試 DB
for _ in $(seq 1 30); do
  if docker exec chilllove-mysql mysqladmin ping -h127.0.0.1 --silent >/dev/null 2>&1; then
    RAILS_ENV=test bin/rails db:create db:migrate >/tmp/setup-db.log 2>&1 \
      && log "test DB 就緒（db:create db:migrate）" \
      || log "⚠ db 準備失敗（見 /tmp/setup-db.log）"
    break
  fi
  sleep 2
done

log "done（best-effort；各段狀態見上方）"
exit 0
