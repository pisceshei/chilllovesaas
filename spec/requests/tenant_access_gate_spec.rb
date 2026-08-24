# frozen_string_literal: true

require "rails_helper"

# 第一道租戶閘（「這個人能不能進這間店」）。
#
# 🔴 這份 spec 存在的理由：對抗式複查（2026-08-24）發現 `Current#can_access_shop?`
# 這個 D8 明文要求的 fail-closed 安全網**方法存在但零 production 呼叫點**，
# 而 `sessions`／`staff_members` 都已升為組織層不帶 `shop_id`。
# 結果是 A 店的 owner 在 B 店的 host 登入即可讀寫 B 店資料。
#
# 兩層是 AND：第一層＝能不能進來（本檔），第二層＝進來能做什麼（policy／authorize_*）。
# 既有的 spec 全部只覆蓋第二層——把第一層整個刪掉，它們仍會全綠。
RSpec.describe "第一道租戶閘：跨店存取", type: :request do
  let!(:shop_a) { create(:shop, subdomain: "gate-a") }
  let!(:shop_b) { create(:shop, subdomain: "gate-b") }

  # A 店的 owner：owner 旗標是**平台級**的，但只有 A 店的指派。
  let!(:owner_a) do
    ActsAsTenant.with_tenant(shop_a) { create(:staff_member, shop: shop_a, owner: true) }
  end

  before do
    https!
    Rack::Attack.cache.store.clear
  end

  def login_at(subdomain, staff)
    host! "#{subdomain}.lvh.me"
    post login_path, params: { email: staff.email, password: "long-password-123" }
  end

  describe "登入側閘（SessionsController#create）" do
    it "A 店 owner 在 A 店可以登入" do
      login_at("gate-a", owner_a)
      expect(response).to redirect_to(admin_root_path)
    end

    it "🔴 A 店 owner 在 B 店的 host 不得登入（owner 是平台級旗標，不是通行證）" do
      login_at("gate-b", owner_a)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(SessionsController::AUTHENTICATION_ERROR)
    end

    it "錯誤訊息與帳密錯誤完全相同（不得洩漏「這個 email 存在」或「這間店存在」）" do
      login_at("gate-b", owner_a)
      cross_tenant_body = response.body

      host! "gate-b.lvh.me"
      post login_path, params: { email: "nobody@example.test", password: "wrong-password-xx" }

      # 兩者都是同一句 AUTHENTICATION_ERROR：登入表單不得成為租戶／帳號枚舉側通道
      expect(response.body).to include(SessionsController::AUTHENTICATION_ERROR)
      expect(cross_tenant_body).to include(SessionsController::AUTHENTICATION_ERROR)
    end
  end

  describe "session 恢復側閘（ApplicationController#resume_admin_session）" do
    # 🔴 這一組的寫法有一段來歷，寫下來免得下一個人重蹈：
    #
    # 我最初寫的是「在 A 店登入 → 把 cookie 帶去 B 店 → 應該被擋」。那三條**全綠**，
    # 但**把恢復側的閘整個拿掉之後它們還是全綠**——因為 admin cookie 是
    # host-only（`config/initializers/session_store.rb` 刻意不設 `domain:`），
    # 測試客戶端根本不會把 gate-a 的 cookie 送到 gate-b。
    # 那三條斷言的是 cookie scope，不是這道閘。**綠得毫無意義。**
    #
    # 恢復側的閘真正管得到的是這個：**session 還活著，但指派被撤銷了**。
    # 只擋登入的話，被踢出商店的人手上那張 cookie 會一直有效到過期。
    it "🔴 指派被撤銷後，手上那張還沒過期的 session 立刻失效" do
      login_at("gate-a", owner_a)
      expect(response).to redirect_to(admin_root_path)

      get admin_root_path
      expect(response).to have_http_status(:ok), "撤銷前應該進得去"

      # 把人從這間店移除（session 本身沒被 revoke，仍在有效期內）
      UserStoreAssignment.where(staff_member_id: owner_a.id, shop_id: shop_a.id).delete_all

      get admin_root_path
      expect(response).to redirect_to(login_path)
    end

    it "🔴 撤銷後連 GraphQL API 也拿不到資料（閘在 controller 基底，一處覆蓋全部）" do
      login_at("gate-a", owner_a)
      UserStoreAssignment.where(staff_member_id: owner_a.id, shop_id: shop_a.id).delete_all

      post admin_graphql_path,
           params: { query: "{ locations { id name } }" }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.body).not_to include("gid://chilllove/Location/")
      codes = response.parsed_body["errors"].to_a.map { |e| e.dig("extensions", "code") }
      expect(codes).to include("ACCESS_DENIED")
    end

    it "指派還在時，同一張 cookie 一直有效（閘擋的是失去資格，不是把人登出）" do
      login_at("gate-a", owner_a)

      3.times do
        get admin_root_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "cookie 本身的跨站邊界（與上面那道閘是兩件事）" do
    # 保留這條是因為它確實是一層防線，但**它證明的是 cookie scope**：
    # admin cookie 沒有 `domain:` ⇒ host-only ⇒ gate-a 的 cookie 不會被送到 gate-b。
    # 🔴 不要把它讀成「恢復側的閘有效」——拿掉那道閘，這條照樣綠。
    it "A 店的 session cookie 不會被送到 B 店的 host" do
      login_at("gate-a", owner_a)

      host! "gate-b.lvh.me"
      get admin_root_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "fail-closed：沒有任何指派的帳號" do
    let!(:orphan) { create(:staff_member, owner: true) }

    it "owner 旗標為 true 但沒有任何店指派 ⇒ 哪一間都進不去" do
      login_at("gate-a", orphan)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
