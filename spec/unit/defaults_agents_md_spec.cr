require "../spec_helper"
require "../../src/services/defaults/agents_md"

describe Hwaro::Services::Defaults::AgentsMd do
  describe ".content" do
    it "returns AGENTS.md content" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should_not be_empty
      content.should contain "AGENTS.md"
    end

    it "includes Essential Commands section" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "Essential Commands"
      content.should contain "hwaro build"
      content.should contain "hwaro serve"
      content.should contain "hwaro new"
    end

    it "includes Content section" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "## Content"
      content.should contain "Pages"
      content.should contain "Front matter uses TOML"
    end

    it "includes Templates section" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "## Templates"
      content.should contain "Jinja2"
      content.should contain "Key Variables"
    end

    it "includes Project Structure" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "Directory Structure"
      content.should contain "config.toml"
      content.should contain "content/"
    end
  end
end
