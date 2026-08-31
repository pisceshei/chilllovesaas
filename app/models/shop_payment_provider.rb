# frozen_string_literal: true

# PSP provider 的租戶側憑證與偏好（G6-3 前半切片）。
#
# ①**這是什麼**：每店 × 每 PSP（airwallex／paypal）一列，承載商家自持商戶號的
#   憑證（15-F4.2：租戶自持、我方只存代理設定）與 method 白名單。與
#   `ShopPaymentMethod`（manual 四型）是兩張表、兩條線。
# ②**值域**：`provider` ∈ `Psp.registry.codes`（平台字典＝limits psp_packs 的鍵——
#   字典平台層、白名單租戶層，鐵律 6）；`environment` ∈ limits
#   `psp_credentials.environment_enum`；`status` ∈ STATUSES（本切片恆 inactive）。
# ③**祕密欄防線（37 §6.3）**：`api_secret`／`webhook_secret` 走 AR encryption
#   （non-deterministic）；儲存時同步計算 SHA-256 前 N hex 指紋（N＝limits
#   `psp_credentials.fingerprint_hex_chars`）供 UI 顯示；**GraphQL 層永不出明文欄**
#   （type 只有 fingerprint）；filter_parameters 既有樣式（:secret）已涵蓋兩欄名。
# ④**enabled_methods 語義**：商家白名單＝三條件交集（15-F4.2）的條件之一，
#   **不是**結帳顯示的唯一輸入——G6-1 另以 capability API＋webhook type∈白名單複驗。
# ⑤🔴 **跨功能影響**：結帳線本切片零讀取（pack enabled:false 閘門不變）；G6-1 adapter
#   讀本表取憑證（job 只帶 id，禁把祕密塞進 Solid Queue payload——limits
#   `psp_credentials.job_payload_forbidden_keys`）；G6-3 的 activation 狀態機與
#   逐方法 toggle 頁接手 status／enabled_methods；平台側（G6-5）另有自己的憑證落點。
class ShopPaymentProvider < ApplicationRecord
  acts_as_tenant :shop

  STATUSES = %w[inactive active].freeze

  encrypts :api_secret
  encrypts :webhook_secret

  # json 欄的表達式預設（`(json_array())`）只在 DB 層生效——**未存檔的新實例拿到 nil**
  # （Rails 不解析 expression default），validate 會誤判。實測踩中（2026-08-31）。
  after_initialize { self.enabled_methods = [] if enabled_methods.nil? }

  validates :provider, presence: true, uniqueness: { scope: :shop_id }
  validate :provider_in_platform_dictionary
  validate :environment_in_enum
  validates :status, inclusion: { in: STATUSES }
  validate :enabled_methods_are_strings

  before_save :refresh_fingerprints

  # @return [Array<String>] 平台字典的 provider 代碼（＝psp_packs 的鍵；鐵律 6 唯一來源）
  def self.provider_dictionary
    Psp.registry.codes.map(&:to_s)
  end

  # @return [Array<String>] 合法環境值（承 carrier.credentials 同名慣例）。
  # 🔴 `Limits.enum` 回**大寫**正規形（GraphQL enum 慣例）——DB 存小寫 ⇒ downcase。
  def self.environments
    Limits.enum(:psp_credentials, :environment_enum).map(&:downcase)
  end

  # 平台層 method 字典（G6-3 分層：字典平台層、白名單租戶層）。
  #
  # @param provider [String]
  # @return [Array<Hash>] [{code:, label:}, …]；未知 provider ⇒ []
  def self.method_dictionary(provider)
    Limits.fetch(:psp_method_dictionary, provider.to_sym)
  rescue KeyError
    []
  end

  private

  def provider_in_platform_dictionary
    return if provider.blank? || self.class.provider_dictionary.include?(provider)

    errors.add(:provider, "不在平台 pack 字典內（psp_packs：#{self.class.provider_dictionary.join('、')}）")
  end

  def environment_in_enum
    return if self.class.environments.include?(environment)

    errors.add(:environment, "必須是 #{self.class.environments.join('|')} 之一")
  end

  def enabled_methods_are_strings
    unless enabled_methods.is_a?(Array) && enabled_methods.all?(String)
      return errors.add(:enabled_methods, "必須是字串陣列（method code 白名單）")
    end

    # 🔴 白名單 ⊆ 平台字典（存顯示名而非字典 code 會讓 G6-1 的
    # 「webhook type ∈ 白名單」server 側複驗永遠不命中——canon-specs 風險項）。
    dictionary = self.class.method_dictionary(provider.to_s).map { |m| m[:code].to_s }
    unknown = enabled_methods - dictionary
    return if unknown.empty?

    errors.add(:enabled_methods, "含字典外的 method code：#{unknown.join('、')}")
  end

  # 37 §6.3：UI 只顯示指紋。祕密欄變更時同步刷新；清空祕密 ⇒ 指紋一併清空。
  # 🔴 指紋算在**明文**上（encrypts 的 getter 回明文）——密文每次加密都不同
  # （non-deterministic），對密文取指紋會讓「同一把 key 重存」看起來像換了 key。
  def refresh_fingerprints
    self.api_secret_fingerprint = fingerprint_of(api_secret) if will_save_change_to_api_secret?
    self.webhook_secret_fingerprint = fingerprint_of(webhook_secret) if will_save_change_to_webhook_secret?
  end

  def fingerprint_of(secret)
    return nil if secret.blank?

    Digest::SHA256.hexdigest(secret).first(Limits.fetch(:psp_credentials, :fingerprint_hex_chars))
  end
end
