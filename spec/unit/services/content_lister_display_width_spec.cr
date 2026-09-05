require "../../spec_helper"

# Follow-up to finding 8: `Logger::Table` measured and padded columns with
# `String#size`, which counts codepoints. A CJK title renders twice as wide as
# its codepoint count, a combining mark renders inside the previous cell, and a
# control byte renders as nothing — so every row after a non-ASCII cell was
# visibly out of line even once the escapes were stripped.
describe Hwaro::Utils::TextUtils do
  describe ".display_width" do
    it "counts ASCII as one column each" do
      Hwaro::Utils::TextUtils.display_width("").should eq(0)
      Hwaro::Utils::TextUtils.display_width("Plain ASCII Title").should eq(17)
    end

    it "counts CJK and Hangul as two columns each" do
      Hwaro::Utils::TextUtils.display_width("한국어").should eq(6)
      Hwaro::Utils::TextUtils.display_width("日本語").should eq(6)
      Hwaro::Utils::TextUtils.display_width("한국어 제목").should eq(11) # 5 wide + 1 space
    end

    it "counts emoji as two columns" do
      Hwaro::Utils::TextUtils.display_width("🚀").should eq(2)
      Hwaro::Utils::TextUtils.display_width("🚀🔥").should eq(4)
      Hwaro::Utils::TextUtils.display_width("ab🚀").should eq(4)
    end

    it "gives combining marks and variation selectors zero width" do
      # "e" + U+0301 COMBINING ACUTE renders in one cell, not two.
      Hwaro::Utils::TextUtils.display_width("é").should eq(1)
      Hwaro::Utils::TextUtils.display_width("café").should eq(4)
      Hwaro::Utils::TextUtils.display_width("café").should eq(4)
      Hwaro::Utils::TextUtils.display_width("❤️").should eq(1)
    end

    it "gives control and format characters zero width" do
      Hwaro::Utils::TextUtils.display_width("\e[31mred\e[0m").should eq(3 + "[31m".size + "[0m".size)
      Hwaro::Utils::TextUtils.display_width("a‍b").should eq(2) # zero-width joiner
      Hwaro::Utils::TextUtils.display_width("ab").should eq(2) # BEL
    end

    it "matches String#size for any ASCII-only string" do
      %w[a ab Status Date Title Path [draft] 2024-01-15 content/posts/hello.md].each do |s|
        Hwaro::Utils::TextUtils.display_width(s).should eq(s.size)
      end
    end
  end

  describe ".pad_display" do
    it "behaves exactly like ljust for ASCII" do
      %w[a ab Title].each do |s|
        Hwaro::Utils::TextUtils.pad_display(s, 8).should eq(s.ljust(8))
      end
    end

    it "pads by columns, not codepoints" do
      # "한국" is 2 codepoints but 4 columns, so a width-6 field needs 2 spaces.
      Hwaro::Utils::TextUtils.pad_display("한국", 6).should eq("한국  ")
    end

    it "never truncates an over-wide cell" do
      Hwaro::Utils::TextUtils.pad_display("한국어", 2).should eq("한국어")
    end
  end
end

describe Hwaro::Logger::Table do
  it "aligns a mixed ASCII / CJK / emoji table on column boundaries" do
    table = Hwaro::Logger::Table.new(["Title", "Path"])
    table.row(["Plain ASCII", "a.md"])
    table.row(["한국어 제목", "b.md"])
    table.row(["emoji 🚀", "c.md"])

    lines = table.render_plain.lines
    # Every row's last column must start at the same terminal column.
    starts = lines.map do |line|
      prefix = line.rpartition("  ").first
      Hwaro::Utils::TextUtils.display_width(prefix)
    end
    starts.uniq.size.should eq(1)
  end

  it "renders an ASCII-only table byte-identically to size-based padding" do
    # Guards the invariant that this change is a no-op for ASCII output.
    table = Hwaro::Logger::Table.new(["Status", "Date", "Title", "Path"])
    table.row(["[pub]", "2024-01-15", "Hello World", "content/hello.md"])
    table.row(["[draft]", "2024-02-01", "Second", "content/second.md"])

    expected = String.build do |io|
      widths = [7, 10, 11, 0]
      io << "  " << "Status".ljust(widths[0]) << "  " << "Date".ljust(widths[1]) << "  " << "Title".ljust(widths[2]) << "  " << "Path" << "\n"
      io << "  " << "[pub]".ljust(widths[0]) << "  " << "2024-01-15".ljust(widths[1]) << "  " << "Hello World".ljust(widths[2]) << "  " << "content/hello.md" << "\n"
      io << "  " << "[draft]".ljust(widths[0]) << "  " << "2024-02-01".ljust(widths[1]) << "  " << "Second".ljust(widths[2]) << "  " << "content/second.md"
    end

    table.render_plain.should eq(expected)
  end

  it "keeps control characters out of the width maths after sanitising" do
    # `tool list` strips escapes first (finding 8); the padded cell must then
    # measure as the visible text only.
    sanitized = Hwaro::Utils::TextUtils.strip_control("\e[31mRED\e[0m")
    table = Hwaro::Logger::Table.new(["Title", "Path"])
    table.row([sanitized, "a.md"])
    table.row(["x", "b.md"])

    lines = table.render_plain.lines
    starts = lines.map { |line| Hwaro::Utils::TextUtils.display_width(line.rpartition("  ").first) }
    starts.uniq.size.should eq(1)
  end
end
