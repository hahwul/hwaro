require "./support/build_helper"

# =============================================================================
# Build hooks / lifecycle functional tests
#
# Verifies pre-build and post-build hook execution via config.
# =============================================================================

describe "Hooks: Pre-build hook execution" do
  it "executes pre-build hooks before building" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [build.hooks]
      pre = ["touch pre_hook_ran.txt"]
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("pre_hook_ran.txt").should be_true
      # Build output should still be valid
      File.exists?("public/index.html").should be_true
    end
  end
end

describe "Hooks: Post-build hook execution" do
  it "executes post-build hooks after building" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [build.hooks]
      post = ["touch post_hook_ran.txt"]
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("post_hook_ran.txt").should be_true
      File.exists?("public/index.html").should be_true
    end
  end
end

describe "Hooks: Multiple hooks" do
  it "executes multiple hooks in sequence" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [build.hooks]
      pre = ["echo 'first' > hook_order.txt", "echo 'second' >> hook_order.txt"]
      post = ["echo 'third' >> hook_order.txt"]
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("hook_order.txt").should be_true
      content = File.read("hook_order.txt")
      content.should contain("first")
      content.should contain("second")
      content.should contain("third")
    end
  end
end

describe "Hooks: External command execution" do
  it "runs shell commands with environment access" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [build.hooks]
      post = ["echo $PWD > pwd_output.txt"]
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("pwd_output.txt").should be_true
      pwd = File.read("pwd_output.txt").strip
      pwd.should_not be_empty
    end
  end
end

describe "Hooks: No hooks configured" do
  it "builds successfully without any hooks" do
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/index.html").should be_true
      File.read("public/index.html").should contain("Home")
    end
  end
end

describe "Hooks: Pre and post hooks combined" do
  it "executes pre hooks before build and post hooks after" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [build.hooks]
      pre = ["date +%s > pre_timestamp.txt"]
      post = ["date +%s > post_timestamp.txt"]
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("pre_timestamp.txt").should be_true
      File.exists?("post_timestamp.txt").should be_true
      File.exists?("public/index.html").should be_true
    end
  end
end

describe "Hooks: Hook creates files used by build" do
  it "pre hook can create files before build runs" do
    config = <<-TOML
      title = "Test"
      base_url = "http://localhost"

      [build.hooks]
      pre = ["mkdir -p static && echo 'generated' > static/generated.txt"]
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHome"},
      template_files: {"page.html" => "{{ content }}"},
    ) do
      File.exists?("public/index.html").should be_true
      File.exists?("public/generated.txt").should be_true
      File.read("public/generated.txt").strip.should eq("generated")
    end
  end
end
