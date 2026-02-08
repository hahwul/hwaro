require "../spec_helper"
require "../../src/services/defaults/agents_md"

describe Hwaro::Services::Defaults::AgentsMd do
  describe ".content" do
    it "returns AGENTS.md content" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should_not be_empty
      content.should contain "AGENTS.md"
    end

    it "includes Hwaro Usage section" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "Hwaro Usage"
      content.should contain "Installation"
      content.should contain "brew install hwaro"
      content.should contain "shards build"
    end

    it "includes Content Management section" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "Content Management"
      content.should contain "Creating New Pages"
      content.should contain "Front Matter Fields"
    end

    it "includes Template Development section" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "Template Development"
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
