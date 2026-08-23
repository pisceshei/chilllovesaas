# frozen_string_literal: true

# `:root` token 區塊的擷取邏輯——由 check-tokens-sync 與 sync-tokens 共用。
#
# 🔴 刻意共用而非各寫一份：兩支腳本若各自實作「怎麼算一個區塊」，
# 同步端與檢查端就可能對邊界有不同看法，於是同步完仍然檢查不過（或反過來，
# 檢查恆綠而實際沒同步）。單一 producer 這條規則對**程式碼本身**也適用。
module TokenBlock
  ROOT = File.expand_path("../..", __dir__)
  PROTOTYPE = File.join(ROOT, "docs", "design", "chilllove-admin-v2.html")
  TOKENS = File.join(ROOT, "app", "assets", "tokens.css")

  # 從文字取出第一個頂層 `:root{ ... \n}` 區塊。
  #
  # 收尾錨點用**行首的 `}`**而非配對括號：值裡有 `linear-gradient(...)`，
  # 註釋裡有中文與各種括號，逐字元配對更容易錯；兩份來源的格式都保證收尾在行首。
  #
  # @param text [String] 來源全文
  # @return [String, nil] 含起訖的區塊文字
  def self.extract(text)
    start = text.index(":root{")
    return nil unless start

    finish = text.index("\n}", start)
    return nil unless finish

    text[start..(finish + 1)]
  end

  # 讀檔並取出區塊，失敗即以退出碼 2 中止（取證失敗與「有漂移」是兩件事）。
  #
  # @param path [String] 檔案絕對路徑
  # @return [String] 區塊文字
  def self.extract_from_file(path)
    unless File.file?(path)
      warn "EVIDENCE_NOT_OBTAINED: 找不到 #{path.sub(ROOT + File::SEPARATOR, '')}"
      exit 2
    end

    # 🔴 一律 binary 讀寫。Ruby 在 Windows 上預設 text mode：讀時 CRLF→LF、
    #    寫時 LF→CRLF，**兩次翻譯會互相抵銷**，於是「逐位元組相同」的檢查在
    #    行尾其實不同的兩份檔案上照樣全綠（本檔第一版即如此：sync 寫出 CRLF、
    #    check 讀回 LF、CI 是 LF-native，三方各自都覺得沒事）。
    #    倉庫 `.gitattributes` 是 `* text=auto eol=lf`，所以 LF 才是這兩份檔的真值。
    block = extract(File.binread(path).force_encoding(Encoding::UTF_8))
    if block.nil?
      warn "EVIDENCE_NOT_OBTAINED: #{path.sub(ROOT + File::SEPARATOR, '')} 裡找不到 `:root{` 區塊"
      exit 2
    end

    block
  end
end
