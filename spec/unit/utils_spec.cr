require "../spec_helper"
require "../../src/utils/text_utils"
require "../../src/utils/sort_utils"
require "../../src/models/page"

# Helper function to create test pages
private def create_test_page(title : String, date : Time? = nil, weight : Int32 = 0) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new("test/#{title.downcase}.md")
  page.title = title
  page.date = date
  page.weight = weight
  page
end

describe Hwaro::Utils::TextUtils do
  describe ".slugify" do
    it "converts text to lowercase" do
      Hwaro::Utils::TextUtils.slugify("Hello World").should eq("hello-world")
    end

    it "replaces spaces with hyphens" do
      Hwaro::Utils::TextUtils.slugify("my blog post").should eq("my-blog-post")
    end

    it "removes special characters" do
      Hwaro::Utils::TextUtils.slugify("Hello! World?").should eq("hello-world")
    end

    it "trims leading and trailing hyphens" do
      Hwaro::Utils::TextUtils.slugify("  hello world  ").should eq("hello-world")
    end

    it "handles multiple spaces" do
      Hwaro::Utils::TextUtils.slugify("hello    world").should eq("hello-world")
    end

    it "handles empty string" do
      Hwaro::Utils::TextUtils.slugify("").should eq("")
    end

    it "removes non-ASCII characters" do
      Hwaro::Utils::TextUtils.slugify("café").should eq("caf")
    end

    it "preserves numbers" do
      Hwaro::Utils::TextUtils.slugify("post 123").should eq("post-123")
    end
  end

  describe ".escape_xml" do
    it "escapes ampersand" do
      Hwaro::Utils::TextUtils.escape_xml("Tom & Jerry").should eq("Tom &amp; Jerry")
    end

    it "escapes less than" do
      Hwaro::Utils::TextUtils.escape_xml("<script>").should eq("&lt;script&gt;")
    end

    it "escapes greater than" do
      Hwaro::Utils::TextUtils.escape_xml("a > b").should eq("a &gt; b")
    end

    it "escapes double quotes" do
      Hwaro::Utils::TextUtils.escape_xml("say \"hello\"").should eq("say &quot;hello&quot;")
    end

    it "escapes single quotes" do
      Hwaro::Utils::TextUtils.escape_xml("it's").should eq("it&apos;s")
    end

    it "escapes multiple special characters" do
      Hwaro::Utils::TextUtils.escape_xml("<a href=\"test\">").should eq("&lt;a href=&quot;test&quot;&gt;")
    end

    it "handles empty string" do
      Hwaro::Utils::TextUtils.escape_xml("").should eq("")
    end

    it "returns text unchanged when no special characters" do
      Hwaro::Utils::TextUtils.escape_xml("hello world").should eq("hello world")
    end
  end

  describe ".strip_html" do
    it "removes HTML tags" do
      Hwaro::Utils::TextUtils.strip_html("<p>Hello</p>").should eq("Hello")
    end

    it "removes nested HTML tags" do
      Hwaro::Utils::TextUtils.strip_html("<div><p>Hello <b>World</b></p></div>").should eq("Hello World")
    end

    it "collapses multiple spaces" do
      Hwaro::Utils::TextUtils.strip_html("<p>Hello</p>   <p>World</p>").should eq("Hello World")
    end

    it "handles empty string" do
      Hwaro::Utils::TextUtils.strip_html("").should eq("")
    end

    it "handles text without HTML" do
      Hwaro::Utils::TextUtils.strip_html("Hello World").should eq("Hello World")
    end
  end
end

describe Hwaro::Utils::SortUtils do
  describe ".compare_by_date" do
    it "returns negative when first page is newer" do
      newer = create_test_page("Newer", Time.utc(2024, 6, 1))
      older = create_test_page("Older", Time.utc(2024, 1, 1))
      Hwaro::Utils::SortUtils.compare_by_date(newer, older).should be < 0
    end

    it "returns positive when first page is older" do
      newer = create_test_page("Newer", Time.utc(2024, 6, 1))
      older = create_test_page("Older", Time.utc(2024, 1, 1))
      Hwaro::Utils::SortUtils.compare_by_date(older, newer).should be > 0
    end

    it "returns zero when dates are equal" do
      date = Time.utc(2024, 6, 1)
      page1 = create_test_page("Page1", date)
      page2 = create_test_page("Page2", date)
      Hwaro::Utils::SortUtils.compare_by_date(page1, page2).should eq(0)
    end

    it "handles nil dates using fallback" do
      with_date = create_test_page("WithDate", Time.utc(2024, 6, 1))
      without_date = create_test_page("WithoutDate", nil)
      # Page without date uses fallback (1970), so with_date is newer
      Hwaro::Utils::SortUtils.compare_by_date(with_date, without_date).should be < 0
    end
  end

  describe ".compare_by_title" do
    it "returns negative when first title comes before alphabetically" do
      page_a = create_test_page("Apple")
      page_b = create_test_page("Banana")
      Hwaro::Utils::SortUtils.compare_by_title(page_a, page_b).should be < 0
    end

    it "returns positive when first title comes after alphabetically" do
      page_a = create_test_page("Apple")
      page_b = create_test_page("Banana")
      Hwaro::Utils::SortUtils.compare_by_title(page_b, page_a).should be > 0
    end

    it "returns zero when titles are equal" do
      page1 = create_test_page("Same")
      page2 = create_test_page("Same")
      Hwaro::Utils::SortUtils.compare_by_title(page1, page2).should eq(0)
    end
  end

  describe ".compare_by_weight" do
    it "returns negative when first weight is lower" do
      light = create_test_page("Light", nil, 1)
      heavy = create_test_page("Heavy", nil, 10)
      Hwaro::Utils::SortUtils.compare_by_weight(light, heavy).should be < 0
    end

    it "returns positive when first weight is higher" do
      light = create_test_page("Light", nil, 1)
      heavy = create_test_page("Heavy", nil, 10)
      Hwaro::Utils::SortUtils.compare_by_weight(heavy, light).should be > 0
    end

    it "returns zero when weights are equal" do
      page1 = create_test_page("Page1", nil, 5)
      page2 = create_test_page("Page2", nil, 5)
      Hwaro::Utils::SortUtils.compare_by_weight(page1, page2).should eq(0)
    end
  end

  describe ".sort_by_date" do
    it "sorts pages by date (newest first)" do
      pages = [
        create_test_page("Old", Time.utc(2024, 1, 1)),
        create_test_page("New", Time.utc(2024, 6, 1)),
        create_test_page("Mid", Time.utc(2024, 3, 1)),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_by_date(pages)
      sorted.map(&.title).should eq(["New", "Mid", "Old"])
    end

    it "reverses order when reverse is true" do
      pages = [
        create_test_page("Old", Time.utc(2024, 1, 1)),
        create_test_page("New", Time.utc(2024, 6, 1)),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_by_date(pages, reverse: true)
      sorted.map(&.title).should eq(["Old", "New"])
    end
  end

  describe ".sort_by_title" do
    it "sorts pages alphabetically" do
      pages = [
        create_test_page("Cherry"),
        create_test_page("Apple"),
        create_test_page("Banana"),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_by_title(pages)
      sorted.map(&.title).should eq(["Apple", "Banana", "Cherry"])
    end

    it "reverses order when reverse is true" do
      pages = [
        create_test_page("Apple"),
        create_test_page("Cherry"),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_by_title(pages, reverse: true)
      sorted.map(&.title).should eq(["Cherry", "Apple"])
    end
  end

  describe ".sort_by_weight" do
    it "sorts pages by weight (lower first)" do
      pages = [
        create_test_page("Heavy", nil, 10),
        create_test_page("Light", nil, 1),
        create_test_page("Medium", nil, 5),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_by_weight(pages)
      sorted.map(&.title).should eq(["Light", "Medium", "Heavy"])
    end

    it "reverses order when reverse is true" do
      pages = [
        create_test_page("Light", nil, 1),
        create_test_page("Heavy", nil, 10),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_by_weight(pages, reverse: true)
      sorted.map(&.title).should eq(["Heavy", "Light"])
    end
  end

  describe ".sort_pages" do
    it "sorts by date by default" do
      pages = [
        create_test_page("Old", Time.utc(2024, 1, 1)),
        create_test_page("New", Time.utc(2024, 6, 1)),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages)
      sorted.map(&.title).should eq(["New", "Old"])
    end

    it "sorts by title when specified" do
      pages = [
        create_test_page("Zebra"),
        create_test_page("Apple"),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages, "title")
      sorted.map(&.title).should eq(["Apple", "Zebra"])
    end

    it "sorts by weight when specified" do
      pages = [
        create_test_page("Heavy", nil, 10),
        create_test_page("Light", nil, 1),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages, "weight")
      sorted.map(&.title).should eq(["Light", "Heavy"])
    end

    it "handles unknown sort_by by defaulting to date" do
      pages = [
        create_test_page("Old", Time.utc(2024, 1, 1)),
        create_test_page("New", Time.utc(2024, 6, 1)),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages, "unknown")
      sorted.map(&.title).should eq(["New", "Old"])
    end

    it "respects reverse parameter" do
      pages = [
        create_test_page("Old", Time.utc(2024, 1, 1)),
        create_test_page("New", Time.utc(2024, 6, 1)),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages, "date", reverse: true)
      sorted.map(&.title).should eq(["Old", "New"])
    end
  end
end
