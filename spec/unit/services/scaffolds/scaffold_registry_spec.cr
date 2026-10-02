require "../../../spec_helper"
require "../../../../src/services/scaffolds/registry"

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

    it "returns Book scaffold" do
      scaffold = Hwaro::Services::Scaffolds::Registry.get(Hwaro::Config::Options::ScaffoldType::Book)
      scaffold.should_not be_nil
      scaffold.type.should eq(Hwaro::Config::Options::ScaffoldType::Book)
    end
  end

  describe ".all" do
    it "returns all registered scaffolds" do
      all = Hwaro::Services::Scaffolds::Registry.all
      all.size.should be >= 5
    end

    it "gives every scaffold a non-empty description" do
      Hwaro::Services::Scaffolds::Registry.all.each(&.description.should_not(be_empty))
    end
  end
end
