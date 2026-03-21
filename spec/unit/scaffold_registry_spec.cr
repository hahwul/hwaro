require "../spec_helper"
require "../../src/services/scaffolds/registry"

describe Hwaro::Services::Scaffolds::Registry do
  describe ".get" do
    it "returns Simple scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Simple)
      scaffold.should_not be_nil
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end

    it "returns Bare scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Bare)
      scaffold.should_not be_nil
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Bare)
    end

    it "returns Blog scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Blog)
      scaffold.should_not be_nil
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Blog)
    end

    it "returns Docs scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Docs)
      scaffold.should_not be_nil
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Docs)
    end

    it "returns BlogDark scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::BlogDark)
      scaffold.should_not be_nil
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::BlogDark)
    end

    it "returns DocsDark scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::DocsDark)
      scaffold.should_not be_nil
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::DocsDark)
    end
  end

  describe ".has?" do
    it "returns true for registered types" do
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Simple).should be_true
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Bare).should be_true
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Blog).should be_true
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::Docs).should be_true
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::BlogDark).should be_true
      Hwaro::Services::Scaffolds::Registry.has?(Hwaro::Config::Options::ScaffoldType::DocsDark).should be_true
    end
  end

  describe ".all" do
    it "returns all registered scaffolds" do
      all = Hwaro::Services::Scaffolds::Registry.all
      all.size.should be >= 6
    end
  end

  describe ".list" do
    it "returns tuples of type name and description" do
      list = Hwaro::Services::Scaffolds::Registry.list
      list.size.should be >= 6
      list.each do |name, description|
        name.should_not be_empty
        description.should_not be_empty
      end
    end

    it "includes all scaffold type names" do
      names = Hwaro::Services::Scaffolds::Registry.list.map(&.[0])
      names.should contain("simple")
      names.should contain("bare")
      names.should contain("blog")
      names.should contain("docs")
      names.should contain("blog-dark")
      names.should contain("docs-dark")
    end
  end

  describe ".default" do
    it "returns Simple scaffold" do
      default = Hwaro::Services::Scaffolds::Registry.default
      default.type.should eq(Hwaro::Config::Options::ScaffoldType::Simple)
    end
  end
end
