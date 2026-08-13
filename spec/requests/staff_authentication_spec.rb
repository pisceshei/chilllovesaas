require "rails_helper"

RSpec.describe "Staff authentication", type: :request do
  let(:shop) { create(:shop, subdomain: "auth-shop", custom_domain: "auth-shop.example") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) do
      create(:staff_member, shop:, email: "owner@example.test", password: "correct-password")
    end
  end

  before do
    host! "auth-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  it "enforces a self-only content security policy on the login surface" do
    get login_path

    expect(response).to have_http_status(:ok)
    expect(response.headers.fetch("Content-Security-Policy")).to include(
      "default-src 'self'",
      "object-src 'none'",
      "frame-ancestors 'none'"
    )
  end

  it "rotates the Rails session and stores only the DB digest" do
    post login_path, params: { email: staff.email, password: "correct-password" }

    expect(response).to redirect_to(admin_root_path)
    expect(response.headers["Set-Cookie"]).to include("_cl_admin")
    expect(response.headers["Set-Cookie"].downcase).to include("httponly")
    expect(response.headers["Set-Cookie"].downcase).to include("samesite=lax")
    # Production session_store is Secure; test intentionally stays HTTP-capable
    # so Rails system-test browsers can retain the cookie.
    expect(Rails.application.config.session_options[:secure]).to be(false)

    raw_token = request.session[:admin_session_token]
    record = ActsAsTenant.with_tenant(shop) { Session.find_by!(staff_member: staff) }
    expect(record.token_digest).to eq(Session.digest(raw_token))
    expect(record.attributes.values).not_to include(raw_token)
  end

  it "uses one Traditional Chinese error for unknown, wrong, and inactive accounts" do
    post login_path, params: { email: "unknown@example.test", password: "wrong-password" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(flash[:alert]).to eq(SessionsController::AUTHENTICATION_ERROR)

    post login_path, params: { email: staff.email, password: "wrong-password" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(flash[:alert]).to eq(SessionsController::AUTHENTICATION_ERROR)

    ActsAsTenant.with_tenant(shop) { staff.update!(status: "deactivated") }
    post login_path, params: { email: staff.email, password: "correct-password" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(flash[:alert]).to eq(SessionsController::AUTHENTICATION_ERROR)
  end

  it "uses the dummy bcrypt path for an invited account without a password" do
    ActsAsTenant.with_tenant(shop) do
      StaffMember.create!(shop:, email: "invited@example.test", status: "invited", owner: false)
    end
    expect(BCrypt::Password).to receive(:new)
      .with(SessionsController::DUMMY_PASSWORD_DIGEST)
      .and_call_original

    post login_path, params: { email: "invited@example.test", password: "wrong-password" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(flash[:alert]).to eq(SessionsController::AUTHENTICATION_ERROR)
  end

  it "revokes the current database session on logout" do
    post login_path, params: { email: staff.email, password: "correct-password" }
    record = ActsAsTenant.with_tenant(shop) { Session.find_by!(staff_member: staff) }

    delete logout_path

    expect(response).to redirect_to(login_path)
    expect(record.reload.revoked_at).to be_present
  end

  it "throttles the eleventh login attempt from one IP even across accounts" do
    10.times do |attempt|
      post login_path, params: { email: "unknown#{attempt}@example.test", password: "wrong-password" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    post login_path, params: { email: "another@example.test", password: "wrong-password" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to be_present
    expect(response.body).to include("嘗試次數過多")
  end

  it "throttles the eleventh account attempt across distributed IPs" do
    10.times do |attempt|
      host!(attempt.even? ? "auth-shop.lvh.me" : "auth-shop.example")
      post login_path,
        params: { email: staff.email, password: "wrong-password" },
        env: { "REMOTE_ADDR" => "203.0.113.#{attempt + 1}" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    host! "auth-shop.example"
    post login_path,
      params: { email: staff.email, password: "wrong-password" },
      env: { "REMOTE_ADDR" => "198.51.100.1" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to be_present
  end
end
