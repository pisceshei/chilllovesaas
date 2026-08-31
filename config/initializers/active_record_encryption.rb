# frozen_string_literal: true

# Active Record encryption 的金鑰接線（全倉第一個使用點＝shop_payment_providers 的
# PSP 憑證欄；37 §6.3「AR Encryption 是最低標」——KMS 信封加密屬待定裁定，本檔不代決）。
#
# 🔴 金鑰載體＝env 三鍵（與現部署一致：bt3 的 /etc/chilllove/env 經 systemd
# EnvironmentFile 與 deploy.sh 的 set -a source 雙通道注入；docs/specs/120 §4 必備鍵
# 清單已同步）。**不用 credentials.yml.enc**——倉庫無 master.key、120 §4 明文
# 「credentials 未使用」；37 §6.3 成文時假設 credentials 載體，與現實衝突處以本檔為準
# （worklog 2026-08-31-G6-3a 記裁定）。
#
# 🔴 production 缺任一鍵＝boot 期就 raise（fail-closed）：靜默跑起來的後果是第一次
# 寫入憑證才炸、或更糟——換了一組隨機金鑰導致既有密文永久不可解。
# dev/test 用固定 dummy 金鑰（僅本機；長度須 ≥ 32 bytes 的 hex 供 key provider 使用）。
Rails.application.configure do
  keys = %w[
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
  ]

  if Rails.env.production?
    missing = keys.reject { |k| ENV[k].present? }
    if missing.any?
      raise "Active Record encryption 金鑰缺失：#{missing.join(', ')}——" \
            "生產環境不得以預設金鑰啟動（/etc/chilllove/env 三鍵，docs/specs/120 §4）"
    end
    primary, deterministic, salt = keys.map { |k| ENV.fetch(k) }
  else
    # dev/test 固定值：讓本機與 CI 不需要 env 檔即可測加密路徑。
    # 🔴 不是秘密（只保護本機開發資料），但**不得**流入 production——上面的分支保證了這一點。
    primary       = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] || "devtest-primary-key-0123456789abcdef"
    deterministic = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] || "devtest-deterministic-0123456789ab"
    salt          = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] || "devtest-salt-0123456789abcdef0123"
  end

  config.active_record.encryption.primary_key = primary
  config.active_record.encryption.deterministic_key = deterministic
  config.active_record.encryption.key_derivation_salt = salt
  # 秘密欄位一律 non-deterministic（limits `psp_credentials.secret_fields_deterministic_forbidden`，
  # 承 carrier.credentials 同名慣例）；deterministic_key 僅為框架必填而接線，目前零使用者。
end
