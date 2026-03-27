require "../spec_helper"

describe Hwaro::Utils::SortUtils do
  describe ".compare_by_date" do
    it "sorts newer page first (descending)" do
      a = Hwaro::Models::Page.new("a.md")
      a.date = Time.utc(2024, 6, 1)
      b = Hwaro::Models::Page.new("b.md")
      b.date = Time.utc(2024, 1, 1)

      Hwaro::Utils::SortUtils.compare_by_date(a, b).should be < 0
    end

    it "prefers updated over date" do
      a = Hwaro::Models::Page.new("a.md")
      a.date = Time.utc(2024, 1, 1)
      a.updated = Time.utc(2024, 12, 1)
      b = Hwaro::Models::Page.new("b.md")
      b.date = Time.utc(2024, 6, 1)

      Hwaro::Utils::SortUtils.compare_by_date(a, b).should be < 0
    end

    it "uses FALLBACK_DATE when no date is set" do
      a = Hwaro::Models::Page.new("a.md")
      a.date = Time.utc(2024, 1, 1)
      b = Hwaro::Models::Page.new("b.md")
      # b has no date -> FALLBACK_DATE (1970)

      Hwaro::Utils::SortUtils.compare_by_date(a, b).should be < 0
    end

    it "breaks ties by path for deterministic ordering" do
      a = Hwaro::Models::Page.new("alpha.md")
      a.date = Time.utc(2024, 1, 1)
      b = Hwaro::Models::Page.new("beta.md")
      b.date = Time.utc(2024, 1, 1)

      Hwaro::Utils::SortUtils.compare_by_date(a, b).should be < 0
    end
  end

  describe ".compare_by_title" do
    it "sorts alphabetically A-Z" do
      a = Hwaro::Models::Page.new("a.md")
      a.title = "Apple"
      b = Hwaro::Models::Page.new("b.md")
      b.title = "Banana"

      Hwaro::Utils::SortUtils.compare_by_title(a, b).should be < 0
    end

    it "sorts Z before A as positive" do
      a = Hwaro::Models::Page.new("a.md")
      a.title = "Zebra"
      b = Hwaro::Models::Page.new("b.md")
      b.title = "Apple"

      Hwaro::Utils::SortUtils.compare_by_title(a, b).should be > 0
    end

    it "returns zero for equal titles" do
      a = Hwaro::Models::Page.new("a.md")
      a.title = "Same"
      b = Hwaro::Models::Page.new("b.md")
      b.title = "Same"

      Hwaro::Utils::SortUtils.compare_by_title(a, b).should eq(0)
    end
  end

  describe ".compare_by_weight" do
    it "sorts lower weight first" do
      a = Hwaro::Models::Page.new("a.md")
      a.weight = 1
      b = Hwaro::Models::Page.new("b.md")
      b.weight = 10

      Hwaro::Utils::SortUtils.compare_by_weight(a, b).should be < 0
    end

    it "returns zero for equal weights" do
      a = Hwaro::Models::Page.new("a.md")
      a.weight = 5
      b = Hwaro::Models::Page.new("b.md")
      b.weight = 5

      Hwaro::Utils::SortUtils.compare_by_weight(a, b).should eq(0)
    end
  end

  describe ".sort_pages" do
    it "sorts by date (newest first) by default" do
      pages = [
        make_page("old.md", Time.utc(2020, 1, 1)),
        make_page("new.md", Time.utc(2024, 1, 1)),
        make_page("mid.md", Time.utc(2022, 1, 1)),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages)
      sorted[0].path.should eq("new.md")
      sorted[1].path.should eq("mid.md")
      sorted[2].path.should eq("old.md")
    end

    it "reverses sort order when reverse is true" do
      pages = [
        make_page("old.md", Time.utc(2020, 1, 1)),
        make_page("new.md", Time.utc(2024, 1, 1)),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages, "date", reverse: true)
      sorted[0].path.should eq("old.md")
      sorted[1].path.should eq("new.md")
    end

    it "sorts by title alphabetically" do
      pages = [
        make_page("c.md", title: "Cherry"),
        make_page("a.md", title: "Apple"),
        make_page("b.md", title: "Banana"),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages, "title")
      sorted[0].title.should eq("Apple")
      sorted[1].title.should eq("Banana")
      sorted[2].title.should eq("Cherry")
    end

    it "sorts by weight ascending" do
      pages = [
        make_page("heavy.md", weight: 10),
        make_page("light.md", weight: 1),
        make_page("mid.md", weight: 5),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages, "weight")
      sorted[0].weight.should eq(1)
      sorted[1].weight.should eq(5)
      sorted[2].weight.should eq(10)
    end

    it "falls back to date sort for unknown sort_by" do
      pages = [
        make_page("old.md", Time.utc(2020, 1, 1)),
        make_page("new.md", Time.utc(2024, 1, 1)),
      ]

      sorted = Hwaro::Utils::SortUtils.sort_pages(pages, "unknown")
      sorted[0].path.should eq("new.md")
      sorted[1].path.should eq("old.md")
    end

    it "handles empty array" do
      sorted = Hwaro::Utils::SortUtils.sort_pages([] of Hwaro::Models::Page)
      sorted.should be_empty
    end

    it "handles single element" do
      pages = [make_page("only.md", Time.utc(2024, 1, 1))]
      sorted = Hwaro::Utils::SortUtils.sort_pages(pages)
      sorted.size.should eq(1)
    end
  end
end

private def make_page(path : String, date : Time? = nil, title : String = "", weight : Int32 = 0) : Hwaro::Models::Page
  page = Hwaro::Models::Page.new(path)
  page.date = date
  page.title = title
  page.weight = weight
  page
end
