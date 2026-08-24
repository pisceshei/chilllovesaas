# frozen_string_literal: true

require "rails_helper"

# 第 25 包磁碟後端：storage_key → 路徑的安全換算。
RSpec.describe Storage::LocalDisk do
  it "寫入／讀出往返；move 原子搬移" do
    key = "shops/1/staged/#{SecureRandom.uuid}/a.png"
    described_class.write(key, StringIO.new("BYTES"))
    expect(described_class.read(key)).to eq("BYTES")
    to = "shops/1/files/#{SecureRandom.uuid}.png"
    described_class.move(key, to)
    expect(described_class.exist?(key)).to be(false)
    expect(described_class.read(to)).to eq("BYTES")
  ensure
    described_class.delete(to) if to
  end

  it "🔴 路徑穿越全拒：..、空段、反斜線、逃根" do
    [ "../secrets", "shops/../../etc/passwd", "shops//x", 'shops/1\x' ].each do |bad|
      expect { described_class.path_for(bad) }
        .to raise_error(described_class::InvalidKey), "#{bad.inspect} 未被擋"
    end
  end
end
