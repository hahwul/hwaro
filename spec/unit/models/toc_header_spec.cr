require "../../spec_helper"
require "../../../src/models/toc"

describe Hwaro::Models::TocHeader do
  describe "#initialize" do
    it "creates a TocHeader with required properties" do
      header = Hwaro::Models::TocHeader.new(
        level: 1,
        id: "introduction",
        title: "Introduction",
        permalink: "/docs/#introduction"
      )

      header.level.should eq(1)
      header.id.should eq("introduction")
      header.title.should eq("Introduction")
      header.permalink.should eq("/docs/#introduction")
    end

    it "initializes with empty children" do
      header = Hwaro::Models::TocHeader.new(
        level: 1,
        id: "test",
        title: "Test",
        permalink: "#test"
      )

      header.children.should be_empty
    end
  end

  describe "#children" do
    it "can add child headers" do
      parent = Hwaro::Models::TocHeader.new(
        level: 1,
        id: "parent",
        title: "Parent",
        permalink: "#parent"
      )

      child = Hwaro::Models::TocHeader.new(
        level: 2,
        id: "child",
        title: "Child",
        permalink: "#child"
      )

      parent.children << child
      parent.children.size.should eq(1)
      parent.children[0].title.should eq("Child")
    end

    it "supports nested children (multi-level TOC)" do
      h1 = Hwaro::Models::TocHeader.new(level: 1, id: "h1", title: "H1", permalink: "#h1")
      h2 = Hwaro::Models::TocHeader.new(level: 2, id: "h2", title: "H2", permalink: "#h2")
      h3 = Hwaro::Models::TocHeader.new(level: 3, id: "h3", title: "H3", permalink: "#h3")

      h2.children << h3
      h1.children << h2

      h1.children.size.should eq(1)
      h1.children[0].children.size.should eq(1)
      h1.children[0].children[0].title.should eq("H3")
      h1.children[0].children[0].level.should eq(3)
    end

    it "can have multiple children" do
      parent = Hwaro::Models::TocHeader.new(level: 1, id: "parent", title: "Parent", permalink: "#parent")

      3.times do |i|
        child = Hwaro::Models::TocHeader.new(
          level: 2,
          id: "child-#{i}",
          title: "Child #{i}",
          permalink: "#child-#{i}"
        )
        parent.children << child
      end

      parent.children.size.should eq(3)
    end
  end

  describe "property mutability" do
    it "allows modifying level" do
      header = Hwaro::Models::TocHeader.new(level: 1, id: "test", title: "Test", permalink: "#test")
      header.level = 2
      header.level.should eq(2)
    end

    it "allows modifying id" do
      header = Hwaro::Models::TocHeader.new(level: 1, id: "old", title: "Test", permalink: "#old")
      header.id = "new"
      header.id.should eq("new")
    end

    it "allows modifying title" do
      header = Hwaro::Models::TocHeader.new(level: 1, id: "test", title: "Old", permalink: "#test")
      header.title = "New"
      header.title.should eq("New")
    end

    it "allows modifying permalink" do
      header = Hwaro::Models::TocHeader.new(level: 1, id: "test", title: "Test", permalink: "#old")
      header.permalink = "#new"
      header.permalink.should eq("#new")
    end
  end

  describe "header levels" do
    it "supports all HTML heading levels (1-6)" do
      (1..6).each do |level|
        header = Hwaro::Models::TocHeader.new(
          level: level,
          id: "h#{level}",
          title: "Heading #{level}",
          permalink: "#h#{level}"
        )
        header.level.should eq(level)
      end
    end
  end
end
