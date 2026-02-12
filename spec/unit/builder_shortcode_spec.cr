require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose the private method for testing
module Hwaro::Core::Build
  class Builder
    def test_parse_shortcode_args_jinja(args_str)
      parse_shortcode_args_jinja(args_str)
    end
  end
end

describe Hwaro::Core::Build::Builder do
  describe "#parse_shortcode_args_jinja" do
    it "parses quoted and unquoted arguments" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja("key1=\"value 1\" key2='value 2' key3=value3")

      args["key1"].should eq("value 1")
      args["key2"].should eq("value 2")
      args["key3"].should eq("value3")
    end

    it "handles empty arguments" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja("")
      args.should be_empty
    end

    it "handles nil arguments" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja(nil)
      args.should be_empty
    end

    it "parses arguments with whitespace" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja("key1 = \"value1\"  key2=  'value2'")

      args["key1"].should eq("value1")
      args["key2"].should eq("value2")
    end
  end
end
