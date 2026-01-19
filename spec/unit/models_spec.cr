require "../spec_helper"

describe Hwaro::Models::Section do
  it "has pagination properties" do
    section = Hwaro::Models::Section.new("wiki/index.md")
    section.paginate.should be_nil
    section.pagination_enabled.should be_nil
  end

  it "can set pagination properties" do
    section = Hwaro::Models::Section.new("wiki/index.md")
    section.paginate = 5
    section.pagination_enabled = true
    section.paginate.should eq(5)
    section.pagination_enabled.should eq(true)
  end
end
