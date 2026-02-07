require "../spec_helper"

describe Hwaro::Content::Processors::TableParser do
  describe ".has_table?" do
    it "returns true when content contains pipe characters" do
      Hwaro::Content::Processors::TableParser.has_table?("| a | b |").should be_true
    end

    it "returns false when content has no pipe characters" do
      Hwaro::Content::Processors::TableParser.has_table?("no table here").should be_false
    end

    it "returns false for empty string" do
      Hwaro::Content::Processors::TableParser.has_table?("").should be_false
    end

    it "returns true for a single pipe character" do
      Hwaro::Content::Processors::TableParser.has_table?("a | b").should be_true
    end
  end

  describe ".process" do
    it "returns content unchanged when no table is present" do
      content = "# Hello\n\nSome paragraph text."
      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should eq(content)
    end

    it "returns empty string unchanged" do
      Hwaro::Content::Processors::TableParser.process("").should eq("")
    end

    it "converts a simple two-column table to HTML" do
      content = <<-MD
      | Header 1 | Header 2 |
      |----------|----------|
      | Cell 1   | Cell 2   |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<table>")
      result.should contain("<thead>")
      result.should contain("<tbody>")
      result.should contain("<th>Header 1</th>")
      result.should contain("<th>Header 2</th>")
      result.should contain("<td>Cell 1</td>")
      result.should contain("<td>Cell 2</td>")
      result.should contain("</table>")
    end

    it "converts a three-column table with alignment" do
      content = <<-MD
      | Left | Center | Right |
      |:-----|:------:|------:|
      | L    | C      | R     |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<th>Left</th>")
      result.should contain("<th style=\"text-align: center;\">Center</th>")
      result.should contain("<th style=\"text-align: right;\">Right</th>")
      result.should contain("<td>L</td>")
      result.should contain("<td style=\"text-align: center;\">C</td>")
      result.should contain("<td style=\"text-align: right;\">R</td>")
    end

    it "handles table without leading/trailing pipes" do
      content = <<-MD
      Header 1 | Header 2
      ---------|--------
      Cell 1   | Cell 2
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<table>")
      result.should contain("<th>Header 1</th>")
      result.should contain("<td>Cell 1</td>")
    end

    it "handles table with multiple body rows" do
      content = <<-MD
      | Name  | Age |
      |-------|-----|
      | Alice | 30  |
      | Bob   | 25  |
      | Carol | 35  |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<td>Alice</td>")
      result.should contain("<td>30</td>")
      result.should contain("<td>Bob</td>")
      result.should contain("<td>25</td>")
      result.should contain("<td>Carol</td>")
      result.should contain("<td>35</td>")
    end

    it "handles table with no body rows (header only)" do
      content = <<-MD
      | Header 1 | Header 2 |
      |----------|----------|
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<table>")
      result.should contain("<thead>")
      result.should contain("<th>Header 1</th>")
      result.should_not contain("<tbody>")
    end

    it "handles left alignment with colon prefix" do
      content = <<-MD
      | Col |
      |:----|
      | Val |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      # Left alignment is default, so no style attribute
      result.should contain("<th>Col</th>")
      result.should contain("<td>Val</td>")
      result.should_not contain("text-align")
    end

    it "handles center alignment" do
      content = <<-MD
      | Col |
      |:---:|
      | Val |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("style=\"text-align: center;\"")
    end

    it "handles right alignment" do
      content = <<-MD
      | Col |
      |----:|
      | Val |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("style=\"text-align: right;\"")
    end

    it "escapes HTML characters in cell content" do
      content = <<-MD
      | Header |
      |--------|
      | <script>alert("xss")</script> |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should_not contain("<script>")
      result.should contain("&lt;script&gt;")
      result.should contain("&quot;")
    end

    it "escapes ampersands in cell content" do
      content = <<-MD
      | Header |
      |--------|
      | Tom & Jerry |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("Tom &amp; Jerry")
    end

    it "preserves content before and after the table" do
      content = <<-MD
      # Title

      Some text before.

      | A | B |
      |---|---|
      | 1 | 2 |

      Some text after.
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("# Title")
      result.should contain("Some text before.")
      result.should contain("<table>")
      result.should contain("Some text after.")
    end

    it "handles rows with fewer columns than headers" do
      content = <<-MD
      | A | B | C |
      |---|---|---|
      | 1 |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<table>")
      result.should contain("<td>1</td>")
      # Should fill missing cells with empty <td> tags
      result.scan(/<td/).size.should be >= 1
    end

    it "handles escaped pipes within cells" do
      content = <<-MD
      | Command |
      |---------|
      | echo \\| grep |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<table>")
      # The escaped pipe should be treated as literal text inside the cell
      result.should contain("|")
    end

    it "handles a single-column table" do
      content = <<-MD
      | Single |
      |--------|
      | Value  |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<table>")
      result.should contain("<th>Single</th>")
      result.should contain("<td>Value</td>")
    end

    it "handles mixed content with multiple tables" do
      content = <<-MD
      | A | B |
      |---|---|
      | 1 | 2 |

      Some middle text.

      | X | Y |
      |---|---|
      | 3 | 4 |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.scan(/<table>/).size.should eq(2)
      result.scan(/<\/table>/).size.should eq(2)
      result.should contain("Some middle text.")
      result.should contain("<td>1</td>")
      result.should contain("<td>3</td>")
    end

    it "does not treat non-table pipe content as a table" do
      content = "This is a | pipe character without a table"
      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should_not contain("<table>")
      result.should eq(content)
    end

    it "handles cells with only whitespace" do
      content = <<-MD
      | A | B |
      |---|---|
      |   |   |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<table>")
      result.should contain("<td></td>")
    end

    it "strips leading and trailing whitespace from cell content" do
      content = <<-MD
      |  Spaced  |
      |----------|
      |  Value   |
      MD

      result = Hwaro::Content::Processors::TableParser.process(content)
      result.should contain("<th>Spaced</th>")
      result.should contain("<td>Value</td>")
    end
  end

  describe Hwaro::Content::Processors::TableParser::Table do
    describe "#to_html" do
      it "generates correct HTML structure" do
        table = Hwaro::Content::Processors::TableParser::Table.new(
          headers: ["Name", "Age"],
          alignments: [
            Hwaro::Content::Processors::TableParser::Alignment::Left,
            Hwaro::Content::Processors::TableParser::Alignment::Right,
          ],
          rows: [["Alice", "30"], ["Bob", "25"]]
        )

        html = table.to_html
        html.should start_with("<table>")
        html.should end_with("</table>")
        html.should contain("<thead>")
        html.should contain("</thead>")
        html.should contain("<tbody>")
        html.should contain("</tbody>")
        html.should contain("<th>Name</th>")
        html.should contain("<th style=\"text-align: right;\">Age</th>")
        html.should contain("<td>Alice</td>")
        html.should contain("<td style=\"text-align: right;\">30</td>")
        html.should contain("<td>Bob</td>")
        html.should contain("<td style=\"text-align: right;\">25</td>")
      end

      it "generates HTML without tbody when no rows" do
        table = Hwaro::Content::Processors::TableParser::Table.new(
          headers: ["Header"],
          alignments: [Hwaro::Content::Processors::TableParser::Alignment::Left],
          rows: [] of Array(String)
        )

        html = table.to_html
        html.should contain("<thead>")
        html.should_not contain("<tbody>")
      end

      it "fills missing cells with empty td tags" do
        table = Hwaro::Content::Processors::TableParser::Table.new(
          headers: ["A", "B", "C"],
          alignments: [
            Hwaro::Content::Processors::TableParser::Alignment::Left,
            Hwaro::Content::Processors::TableParser::Alignment::Left,
            Hwaro::Content::Processors::TableParser::Alignment::Left,
          ],
          rows: [["only one"]]
        )

        html = table.to_html
        # Should have 3 td elements: 1 with content + 2 empty
        html.scan(/<td/).size.should eq(3)
      end

      it "applies center alignment to all cells in a column" do
        table = Hwaro::Content::Processors::TableParser::Table.new(
          headers: ["Center"],
          alignments: [Hwaro::Content::Processors::TableParser::Alignment::Center],
          rows: [["value"]]
        )

        html = table.to_html
        html.should contain("<th style=\"text-align: center;\">Center</th>")
        html.should contain("<td style=\"text-align: center;\">value</td>")
      end

      it "escapes HTML entities in headers and cells" do
        table = Hwaro::Content::Processors::TableParser::Table.new(
          headers: ["<b>Bold</b>"],
          alignments: [Hwaro::Content::Processors::TableParser::Alignment::Left],
          rows: [["Tom & Jerry"]]
        )

        html = table.to_html
        html.should contain("&lt;b&gt;Bold&lt;/b&gt;")
        html.should contain("Tom &amp; Jerry")
      end

      it "handles mixed alignments across columns" do
        table = Hwaro::Content::Processors::TableParser::Table.new(
          headers: ["Left", "Center", "Right"],
          alignments: [
            Hwaro::Content::Processors::TableParser::Alignment::Left,
            Hwaro::Content::Processors::TableParser::Alignment::Center,
            Hwaro::Content::Processors::TableParser::Alignment::Right,
          ],
          rows: [["L", "C", "R"]]
        )

        html = table.to_html
        html.should contain("<th>Left</th>")
        html.should contain("<th style=\"text-align: center;\">Center</th>")
        html.should contain("<th style=\"text-align: right;\">Right</th>")
        html.should contain("<td>L</td>")
        html.should contain("<td style=\"text-align: center;\">C</td>")
        html.should contain("<td style=\"text-align: right;\">R</td>")
      end
    end
  end

  describe Hwaro::Content::Processors::TableParser::Alignment do
    it "has Left variant" do
      Hwaro::Content::Processors::TableParser::Alignment::Left.should_not be_nil
    end

    it "has Center variant" do
      Hwaro::Content::Processors::TableParser::Alignment::Center.should_not be_nil
    end

    it "has Right variant" do
      Hwaro::Content::Processors::TableParser::Alignment::Right.should_not be_nil
    end
  end
end
