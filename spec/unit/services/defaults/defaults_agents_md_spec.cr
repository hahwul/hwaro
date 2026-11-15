require "../../../spec_helper"
require "../../../../src/services/defaults/agents_md"

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
      content.should contain "Front matter can use TOML"
      content.should contain "YAML"
      content.should contain "JSON"
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

    it "includes Site-Specific Instructions section" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "Site-Specific Instructions"
    end

    it "lists correct Crinja join filter syntax" do
      content = Hwaro::Services::Defaults::AgentsMd.content
      content.should contain "join(\", \")"
      content.should_not contain "join(sep="
    end
  end

  describe ".remote_content" do
    it "returns remote AGENTS.md content" do
      content = Hwaro::Services::Defaults::AgentsMd.remote_content
      content.should_not be_empty
      content.should contain "AGENTS.md"
    end

    it "includes Essential Commands" do
      content = Hwaro::Services::Defaults::AgentsMd.remote_content
      content.should contain "Essential Commands"
      content.should contain "hwaro build"
      content.should contain "hwaro serve"
    end

    it "includes links to online documentation" do
      content = Hwaro::Services::Defaults::AgentsMd.remote_content
      content.should contain "hwaro.hahwul.com"
      content.should contain "llms-full.txt"
    end

    it "includes Notes for AI Agents" do
      content = Hwaro::Services::Defaults::AgentsMd.remote_content
      content.should contain "Notes for AI Agents"
      content.should contain "Front matter** can be TOML"
    end

    it "includes Site-Specific Instructions section" do
      content = Hwaro::Services::Defaults::AgentsMd.remote_content
      content.should contain "Site-Specific Instructions"
    end

    it "is shorter than local content" do
      remote = Hwaro::Services::Defaults::AgentsMd.remote_content
      local = Hwaro::Services::Defaults::AgentsMd.content
      remote.size.should be < local.size
    end
  end

  # Its own note 7 says to keep `| e` on user content; a snippet an agent
  # copies must follow it, or it prints titles raw with autoescape = false.
  it "keeps | e on the titles its template snippets print into HTML" do
    content = Hwaro::Services::Defaults::AgentsMd.content
    snippets = content.scan(/```jinja\n(.*?)```/m).map(&.[1]).join
    bare = snippets.scan(/<a [^>]*>[^<]*\{\{\s*[\w.]*title\s*\}\}/).map(&.[0])
    bare.should be_empty
  end
end
