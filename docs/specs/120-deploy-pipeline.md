# 120 — 部署管線規格（CD-1 walking skeleton 版，2026-08-23）

> 依 `docs/plans/2026-08-18-總方案.md` §八 CD-1 建立。本版只覆蓋 walking skeleton
> 實際落地的部分；每個「⏸ 待辦」都標明缺什麼輸入。D40（2026-08-23）後合併閘門＝
> CI `quality`＋`test` 兩 job 綠。

## 1. 拓撲（實測 2026-08-23）

| 項 | 值 | 取證方式 |
|---|---|---|
| 主機 | bt3（Ubuntu 26.04 LTS，16C／22GB／466GB） | `ssh bt3-wan` 實測 |
| LAN 位址 | 192.168.31.246 | `hostname -I` |
| WAN 入口 | `bt3.chilling.com.hk`：16890→SSH、23823→BT 面板 | 本機 curl／ssh 實測 |
| ⚠️ WAN 80／443 | 由**另一台機器**的 nginx 佔用（bt3 無監聽仍回應） | curl 對照 `ss -tlnp` |
| ⇒ 對外 HTTP 入口 | **⏸ 待使用者提供**：路由器加一條轉發（建議 28080→192.168.31.246:80），或前置 nginx 加 vhost 反代 | — |

## 2. 伺服器組件與版本（apt，2026-08-23 安裝）

MySQL 8.4.10（socket auth root、業務庫走 `chilllove` 專用帳號）｜nginx 1.28.3｜
Node 22.22.1＋pnpm 11.16.0（`packageManager` 同值）｜Ruby 3.4.10（rbenv＋ruby-build，
`RBENV_ROOT=/opt/rbenv`，與 `.ruby-version` 一致）。

## 3. 檔案佈局與職責

| 位置（伺服器） | 內容 | 來源 |
|---|---|---|
| `/www/wwwroot/chilllove/app` | 倉庫 clone（`chilllove` 使用者持有） | `git fetch`＋detach checkout |
| `/etc/chilllove/env` | 秘密（root:chilllove 0640，**不進 Git**） | 首次手建，見 §4 |
| `/etc/systemd/system/chilllove-puma.service` | puma 單元（Solid Queue 跑在 puma 內） | 倉庫 `config/deploy/` 由 deploy.sh 同步 |
| `/etc/nginx/sites-available/chilllove` | 80 反代＋`/vite/` 靜態直出 | 同上 |

## 4. `/etc/chilllove/env` 契約

必備：`RAILS_ENV=production`、`SECRET_KEY_BASE`（`rails secret` 產生；倉庫無
master.key，credentials 未使用）、`CHILLLOVE_DATABASE_PASSWORD`、`SOLID_QUEUE_IN_PUMA=1`、
`DISABLE_FORCE_SSL=1`（🔴 明文過渡期專用——TLS 終結就緒後**必須移除**，Rails 側
fail-secure：未設定＝force_ssl＋assume_ssl 全開，見 `config/environments/production.rb`）。
Seed 專用（跑 seed 那次才帶）：`SEED_DEMO_SHOP=1`、`SEED_ADMIN_PASSWORD`。

## 5. 部署程序

每步部署＝在伺服器上 `bash scripts/deploy.sh [ref]`（預設 origin/main；七步：
取碼→bundle→pnpm＋assets→db:prepare→同步配置→重啟 puma→`/up` 健康檢查 30 次×2s，
失敗非零退出）。冪等；秘密只經 `/etc/chilllove/env` 注入。

## 6. ⏸ 待辦（缺輸入或缺裁定，不在本版射程）

1. **TLS 終結**：缺對外 80／443 路徑（§1 最後一列）＋憑證簽發方式（Let's Encrypt
   HTTP-01 需 80 直達；DNS-01 需 DNS 商 API token）。
2. **異地備份**（總方案 §十二第 1 條）：object storage provider／bucket／費用上限
   由使用者提供後啟用每日 dump＋binlog 加密外送＋還原演練。
3. **deploy 由 GitHub Actions 觸發（CD-2）**：現為 SSH 手跑；接 Actions 需 secrets
   （SSH 私鑰）落 repo settings。
4. **rollback 自動化（CD-3）**：現狀＝`deploy.sh <舊 ref>` 手動回滾；故障注入演練待做。
