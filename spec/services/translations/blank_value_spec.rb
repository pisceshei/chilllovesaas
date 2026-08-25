# frozen_string_literal: true

require "rails_helper"

# 第 7 包：空值判準（67 §C.4(b)）。純函式，不碰 DB。
#
# 🔴 這支 spec 的 fixture 是**兩個方向都要窮舉**的：
#   - 判「空」錯了 ⇒ 商家看到空白區塊而不是原文（fallback 永遠不觸發）
#   - 判「非空」錯了 ⇒ `Upsert` 執行 `delete_all`，**商家的譯文被靜默刪掉**
#   後者不可逆，所以有疑慮時一律往「非空」倒。
#
# 🔴 **不可見字元一律寫 `\uXXXX` 跳脫，不放字面字元**：字面 ZWSP／BOM 在編輯器、
#   git diff、code review 裡全都看不見，改壞了沒有人會發現（本包寫檔時也踩過字面 NUL）。
RSpec.describe Translations::BlankValue do
  P7_NBSP = "\u00A0"       # 不斷行空白
  P7_IDEOGRAPHIC = "\u3000" # 全形空白
  P7_ZWSP = "\u200B"       # 零寬空白
  P7_BOM = "\uFEFF"        # 位元組順序記號
  P7_LRM = "\u200E"        # 由左至右標記

  # 立本規則之前 `Upsert#blank_value?` 判錯的八格（2026-08-25 實跑對照，本檔第一版即為修正對象）。
  P7_REGRESSED_BY_OLD_IMPL = [
    "<p>&#160;</p>",              # 數字實體形式的 NBSP：舊實作只認字面 &nbsp;
    "<p>#{P7_IDEOGRAPHIC}</p>",      # 全形空白 U+3000：舊實作的 \s 不含它
    "<p>#{P7_ZWSP}</p>",             # ZWSP：同上
    '<p class="x"></p>',          # 帶屬性的 p：舊實作的 </?p> 正則對不上
    "<div><p></p></div>",         # 巢狀空容器
    "<p>#{P7_ZWSP}#{P7_BOM}</p>",       # ZWSP + BOM
    "<p><span></span></p>",       # 空 span
    "<ul><li></li></ul>"          # 空清單
  ].freeze

  describe ".blank?(kind: :html)" do
    {
      # ---- 應判空（fallback 必須觸發）----
      "" => true,
      "   " => true,
      "\n\t " => true,
      "<p></p>" => true,
      "<p><br></p>" => true,
      "<p><br/></p>" => true,
      "<p>&nbsp;</p>" => true,
      "<p>&#160;</p>" => true,
      "<p>#{P7_IDEOGRAPHIC}</p>" => true,
      "<p>#{P7_NBSP}</p>" => true,
      "<p>#{P7_ZWSP}</p>" => true,
      "<p>#{P7_ZWSP}#{P7_BOM}</p>" => true,
      "<p>#{P7_LRM}</p>" => true,
      '<p class="x"></p>' => true,
      "<div><p></p></div>" => true,
      "<p><span></span></p>" => true,
      "<ul><li></li></ul>" => true,
      "<p><br><br><br></p>" => true,
      # ---- 應判非空（誤刪＝不可逆）----
      "<p>你好</p>" => false,
      "<div>text</div>" => false,
      "<p>0</p>" => false,
      "&amp;" => false,
      "<ul><li>a</li></ul>" => false,
      '<p><img src="/a.png"></p>' => false,   # 只有圖沒有字，仍然是內容
      "<hr>" => false,
      "<table><tr><td></td></tr></table>" => false,
      '<iframe src="/v"></iframe>' => false,
      "<video src=x></video>" => false,
      "<p><img src=x" => false                # 截斷 HTML：HTML4 保留 img ⇒ 不誤刪
    }.each do |html, expected|
      it "#{html.inspect} → #{expected}" do
        expect(described_class.blank?(html, kind: :html)).to eq(expected)
      end
    end

    it "nil 判空" do
      expect(described_class.blank?(nil, kind: :html)).to be(true)
    end
  end

  describe ".blank?(kind: :text)" do
    it "🔴 純文字欄裡的 `<p></p>` 是真內容（帶角括號的標題），不判空" do
      expect(described_class.blank?("<p></p>", kind: :text)).to be(false)
    end

    it "不可見字元仍然判空（全形空白／NBSP／ZWSP／BOM／LRM）" do
      [ P7_IDEOGRAPHIC, P7_NBSP, P7_ZWSP, P7_BOM, P7_LRM, " \t\n" ].each do |value|
        expect(described_class.blank?(value, kind: :text)).to be(true), "#{value.inspect} 應判空"
      end
    end

    it "預設 kind 是 :text（呼叫端漏帶時走比較不會誤刪的那一側）" do
      expect(described_class.blank?("<p></p>")).to be(false)
    end
  end

  describe "🔴 回歸：舊 regex 實作判錯的八格" do
    P7_REGRESSED_BY_OLD_IMPL.each do |html|
      it "#{html.inspect} 現在判空（舊實作判非空 ⇒ 前台顯示空白區塊）" do
        expect(described_class.blank?(html, kind: :html)).to be(true)
      end
    end

    it "舊實作的八格**沒有**反向誤判（沒有把有內容的判成空）" do
      # 這一格把「本次修正只往一個方向動」寫成可執行的斷言：舊實作在測試矩陣裡
      # 從未把「有內容」判成「空」⇒ 本次修正不會刪到任何既有資料。
      old_blank = lambda do |value|
        text = value.to_s
        next true if text.strip.empty?

        text.gsub(%r{<br\s*/?>|&nbsp;|\s}i, "").gsub(%r{</?p>}i, "").empty?
      end
      has_content = [ "<p>你好</p>", "<div>text</div>", "<p>0</p>", '<p><img src="/a.png"></p>', "<hr>" ]
      has_content.each do |html|
        expect(old_blank.call(html)).to be(false), "#{html.inspect} 舊實作竟然判空"
        expect(described_class.blank?(html, kind: :html)).to be(false)
      end
    end
  end

  describe "CONTENT_BEARING 的邊界" do
    it "🔴 br 不在清單裡（`<p><br></p>` 是 RTE 初始值，正是要抓的形態）" do
      expect(described_class::CONTENT_BEARING).not_to include("br")
    end

    it "🔴 不可見的 void 元素不在清單裡（判準是「看不看得到」，不是 void elements 清單）" do
      expect(described_class::CONTENT_BEARING).not_to include("area", "base", "col", "link", "meta", "wbr")
    end
  end
end
