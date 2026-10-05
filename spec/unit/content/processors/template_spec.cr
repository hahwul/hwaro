require "../../../spec_helper"

# Builds a minimal `__menus__` Crinja value shape ({lang => {menu_name =>
# [{"name" => ...}]}}) for the `get_menu function` tests below — just
# enough for the function's own language-resolution logic to exercise,
# not the full Entry shape `Content::Menus`/`build_global_vars` produce.
private def menus_value(structure : Hash(String, Hash(String, Array(String)))) : Crinja::Value
  lang_hash = {} of String => Crinja::Value
  structure.each do |lang, menus|
    menu_hash = {} of String => Crinja::Value
    menus.each do |menu_name, names|
      entries = names.map { |n| Crinja::Value.new({"name" => Crinja::Value.new(n)}) }
      menu_hash[menu_name] = Crinja::Value.new(entries)
    end
    lang_hash[lang] = Crinja::Value.new(menu_hash)
  end
  Crinja::Value.new(lang_hash)
end

describe Hwaro::Content::Processors::TemplateEngine do
  describe "Custom Filters" do
    it "processes slugify filter" do
      vars = {} of String => Crinja::Value

      vars["text"] = Crinja::Value.new("Hello World! This is a Test")

      template = "{{ text | slugify }}"
      result = render_crinja(template, vars)
      result.should eq("hello-world-this-is-a-test")
    end

    it "processes strip_html filter" do
      vars = {} of String => Crinja::Value

      vars["html"] = Crinja::Value.new("<p>Hello <strong>World</strong></p>")

      template = "{{ html | strip_html }}"
      result = render_crinja(template, vars)
      result.should eq("Hello World")
    end

    it "processes truncate_words filter" do
      vars = {} of String => Crinja::Value

      vars["text"] = Crinja::Value.new("one two three four five six seven eight nine ten")

      template = "{{ text | truncate_words(length=5) }}"
      result = render_crinja(template, vars)
      result.should eq("one two three four five...")
    end

    it "processes xml_escape filter" do
      vars = {} of String => Crinja::Value

      vars["text"] = Crinja::Value.new("<tag attr=\"value\">content</tag>")

      template = "{{ text | xml_escape }}"
      result = render_crinja(template, vars)
      result.should eq("&lt;tag attr=&quot;value&quot;&gt;content&lt;/tag&gt;")
    end

    it "processes date filter with format" do
      vars = {} of String => Crinja::Value
      time = Time.utc(2023, 10, 5, 12, 0, 0)

      vars["my_date"] = Crinja::Value.new(Crinja::Value.new(time))

      template = "{{ my_date | date(format=\"%Y/%m/%d\") }}"
      result = render_crinja(template, vars)
      result.should eq("2023/10/05")
    end

    it "processes date filter with string input" do
      vars = {} of String => Crinja::Value

      vars["date_str"] = Crinja::Value.new("2023-10-05")

      template = "{{ date_str | date(format=\"%d-%m-%Y\") }}"
      result = render_crinja(template, vars)
      result.should eq("05-10-2023")
    end

    it "processes absolute_url filter" do
      vars = {} of String => Crinja::Value
      vars["base_url"] = Crinja::Value.new("https://example.com")

      vars["path"] = Crinja::Value.new("/about/")

      template = "{{ path | absolute_url }}"
      result = render_crinja(template, vars)
      result.should eq("https://example.com/about/")
    end

    it "processes relative_url filter" do
      vars = {} of String => Crinja::Value
      vars["base_url"] = Crinja::Value.new("https://example.com/blog")

      vars["path"] = Crinja::Value.new("/post/1/")

      template = "{{ path | relative_url }}"
      result = render_crinja(template, vars)
      result.should eq("/blog/post/1/")
    end

    it "processes markdownify filter" do
      vars = {} of String => Crinja::Value

      vars["markdown"] = Crinja::Value.new("**Bold**")

      template = "{{ markdown | markdownify }}"
      result = render_crinja(template, vars)
      result.should contain("<strong>Bold</strong>")
    end

    it "processes jsonify filter" do
      vars = {} of String => Crinja::Value

      vars["data"] = Crinja::Value.new("test string")

      template = "{{ data | jsonify }}"
      result = render_crinja(template, vars)
      result.should contain("\"test string\"")
    end

    it "processes where filter" do
      vars = {} of String => Crinja::Value

      items = [
        {"name" => "A", "type" => "fruit"},
        {"name" => "B", "type" => "vegetable"},
        {"name" => "C", "type" => "fruit"},
      ]
      items_val = items.map do |item|
        h = {} of String => Crinja::Value
        item.each { |k, v| h[k] = Crinja::Value.new(v) }
        Crinja::Value.new(h)
      end
      vars["items"] = Crinja::Value.new(Crinja::Value.new(items_val))

      template = "{% for item in items | where(attribute=\"type\", value=\"fruit\") %}{{ item.name }},{% endfor %}"
      result = render_crinja(template, vars)
      result.should eq("A,C,")
    end

    it "processes sort_by filter" do
      vars = {} of String => Crinja::Value

      items = [
        {"name" => "C"},
        {"name" => "A"},
        {"name" => "B"},
      ]
      items_val = items.map do |item|
        h = {} of String => Crinja::Value
        item.each { |k, v| h[k] = Crinja::Value.new(v) }
        Crinja::Value.new(h)
      end
      vars["items"] = Crinja::Value.new(Crinja::Value.new(items_val))

      template = "{% for item in items | sort_by(attribute=\"name\") %}{{ item.name }}{% endfor %}"
      result = render_crinja(template, vars)
      result.should eq("ABC")
    end

    it "processes group_by filter" do
      vars = {} of String => Crinja::Value

      items = [
        {"name" => "Apple", "type" => "fruit"},
        {"name" => "Carrot", "type" => "vegetable"},
        {"name" => "Banana", "type" => "fruit"},
      ]
      items_val = items.map do |item|
        h = {} of String => Crinja::Value
        item.each { |k, v| h[k] = Crinja::Value.new(v) }
        Crinja::Value.new(h)
      end
      vars["items"] = Crinja::Value.new(Crinja::Value.new(items_val))

      template = "{% for group in items | group_by(attribute=\"type\") %}{{ group.grouper }}:{% for item in group.list %}{{ item.name }},{% endfor %};{% endfor %}"
      result = render_crinja(template, vars)
      result.should contain("fruit:Apple,Banana,;")
      result.should contain("vegetable:Carrot,;")
    end

    it "processes split filter" do
      vars = {} of String => Crinja::Value

      vars["text"] = Crinja::Value.new("a,b,c")

      template = "{% for part in text | split(pat=\",\") %}{{ part }}-{% endfor %}"
      result = render_crinja(template, vars)
      result.should eq("a-b-c-")
    end

    it "processes safe filter" do
      vars = {} of String => Crinja::Value

      vars["html"] = Crinja::Value.new("<b>Bold</b>")

      # Since autoescape is disabled globally in TemplateEngine, we might need to test environment behavior
      # But safe filter explicitly returns SafeString.
      template = "{{ html | safe }}"
      result = render_crinja(template, vars)
      result.should eq("<b>Bold</b>")
    end

    it "processes trim filter" do
      vars = {} of String => Crinja::Value

      vars["text"] = Crinja::Value.new("  hello  ")

      template = "'{{ text | trim }}'"
      result = render_crinja(template, vars)
      result.should eq("'hello'")
    end
  end

  describe "Custom Tests" do
    it "processes startswith test" do
      vars = {} of String => Crinja::Value
      vars["page_url"] = Crinja::Value.new("/blog/post/")

      template = "{% if page_url is startswith(\"/blog/\") %}yes{% else %}no{% endif %}"
      result = render_crinja(template, vars)
      result.should eq("yes")
    end

    it "processes endswith test" do
      vars = {} of String => Crinja::Value
      vars["page_title"] = Crinja::Value.new("Hello World!")

      template = "{% if page_title is endswith(\"!\") %}yes{% else %}no{% endif %}"
      result = render_crinja(template, vars)
      result.should eq("yes")
    end

    it "processes containing test" do
      vars = {} of String => Crinja::Value
      vars["page_url"] = Crinja::Value.new("/products/software/")

      template = "{% if page_url is containing(\"products\") %}yes{% else %}no{% endif %}"
      result = render_crinja(template, vars)
      result.should eq("yes")
    end

    it "tests list containment by element, not by the list's text" do
      vars = {"tags" => Crinja.value(["C++", "Crystal"])}
      render_crinja(%({{ tags is containing("Crystal") }}|{{ tags is containing("C") }}|{{ tags is containing(", ") }}), vars)
        .should eq("true|false|false")
    end

    it "treats undefined and empty safe strings as empty, not present" do
      vars = {"extra" => Crinja.value({"a" => "x"})}
      render_crinja(%({{ extra.missing is present }}|{{ extra.missing is empty }}|{{ ("" | safe) is empty }}|{{ extra.a is present }}), vars)
        .should eq("false|true|true|true")
    end

    it "processes defined test" do
      vars = {} of String => Crinja::Value
      vars["page_title"] = Crinja::Value.new("A title")

      template = "{% if page_title is defined %}yes{% else %}no{% endif %}"
      result = render_crinja(template, vars)
      result.should eq("yes")
    end

    it "returns false for matching test with an invalid regex (no raise)" do
      vars = {} of String => Crinja::Value

      vars["u"] = Crinja::Value.new("anything")

      # Unbalanced bracket "[" is an invalid regex; the rescue ArgumentError
      # branch must return false rather than letting the error abort the build.
      template = "{% if u is matching(\"[\") %}HIT{% else %}MISS{% endif %}"
      result = render_crinja(template, vars)
      result.should eq("MISS")
    end

    it "matches consistently across repeated renders with a valid regex (cached)" do
      vars = {} of String => Crinja::Value

      vars["u"] = Crinja::Value.new("photo.png")

      template = "{% if u is matching(\"[.](jpg|png)$\") %}HIT{% else %}MISS{% endif %}"
      render_crinja(template, vars).should eq("HIT")
      # Second render hits the cached compiled regex and must yield the same result.
      render_crinja(template, vars).should eq("HIT")
    end
  end

  describe "Custom Functions" do
    it "processes now function" do
      vars = {} of String => Crinja::Value

      template = "{{ now() }}"
      result = render_crinja(template, vars)
      # Should contain a date-like string
      result.should match(/\d{4}-\d{2}-\d{2}/)
    end

    it "processes now function with explicit format argument" do
      vars = {} of String => Crinja::Value

      template = "{{ now(format=\"%Y\") }}"
      result = render_crinja(template, vars)
      # Explicit format branch should pass the format through to time.to_s
      result.should match(/^\d{4}$/)
      result.should eq(Time.local.year.to_s)
    end

    it "processes env function with set variable" do
      ENV["HWARO_TPL_TEST"] = "analytics-123"
      vars = {} of String => Crinja::Value

      template = %({{ env("HWARO_TPL_TEST") }})
      result = render_crinja(template, vars)
      result.should eq("analytics-123")
    ensure
      ENV.delete("HWARO_TPL_TEST")
    end

    it "processes env function with default when unset" do
      ENV.delete("HWARO_TPL_MISS")
      vars = {} of String => Crinja::Value

      template = %({{ env("HWARO_TPL_MISS", default="fallback") }})
      result = render_crinja(template, vars)
      result.should eq("fallback")
    end

    it "processes env function with default when empty" do
      ENV["HWARO_TPL_EMPTY"] = ""
      vars = {} of String => Crinja::Value

      template = %({{ env("HWARO_TPL_EMPTY", default="fallback") }})
      result = render_crinja(template, vars)
      result.should eq("fallback")
    ensure
      ENV.delete("HWARO_TPL_EMPTY")
    end

    it "processes env function returns empty string when unset without default" do
      ENV.delete("HWARO_TPL_NODEF")
      vars = {} of String => Crinja::Value

      template = %([{{ env("HWARO_TPL_NODEF") }}])
      result = render_crinja(template, vars)
      result.should eq("[]")
    end

    it "processes url_for function" do
      vars = {} of String => Crinja::Value
      vars["base_url"] = Crinja::Value.new("https://example.com")

      template = "{{ url_for(path=\"/about/\") }}"
      result = render_crinja(template, vars)
      result.should eq("https://example.com/about/")
    end

    it "load_data parses CSV cells (stripped) from a project-relative path" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("data")
          # Cells include surrounding whitespace to confirm .strip is applied.
          File.write("data/menu.csv", "name , price\n Tea , 3 \n")

          vars = {} of String => Crinja::Value

          template = "{% set d = load_data(path=\"data/menu.csv\") %}{{ d[1][0] }}|{{ d[1][1] }}"
          result = render_crinja(template, vars)
          result.should eq("Tea|3")
        end
      end
    end

    it "load_data reads a data file that starts with a UTF-8 BOM, like site.data" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("data")
          File.write("data/bom.json", "\uFEFF{\"bom\": 1}")
          Hwaro::Content::Processors::TemplateEngine.clear_load_data_cache

          render_crinja(%({{ load_data(path="data/bom.json").bom }})).should eq("1")
        end
      end
    end

    it "load_data blocks path traversal outside the project root" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          vars = {} of String => Crinja::Value

          Hwaro::Content::Processors::TemplateEngine.clear_load_data_cache
          template = "[{{ load_data(path=\"../../../etc/passwd\") }}]"
          log = with_captured_log do
            result = render_crinja(template, vars)
            # Boundary check fails -> result stays Crinja nil. Crinja renders nil
            # as the literal "none", so the traversal yields no file contents.
            result.should eq("[none]")
          end
          # Refused either way — as "outside the project" when the target
          # exists, or as "not a file" when the climb lands nowhere.
          log.should contain("load_data(\"../../../etc/passwd\")")
          log.should contain("the template receives none")
        end
      end
    end

    # A typo'd path rendered as a bare `none` with nothing in the log, so an
    # empty menu built from `load_data(path="data/meun.json")` looked exactly
    # like an intentionally empty one. Warn once per path per build, not once
    # per page.
    it "load_data warns once per build about a missing file" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          Hwaro::Content::Processors::TemplateEngine.clear_load_data_cache
          vars = {} of String => Crinja::Value

          template = "[{{ load_data(path=\"data/meun.json\") }}]"
          log = with_captured_log do
            render_crinja(template, vars).should eq("[none]")
            render_crinja(template, vars).should eq("[none]")
          end
          log.scan("load_data(\"data/meun.json\") is not a file").size.should eq(1)

          # The next build must report it again.
          Hwaro::Content::Processors::TemplateEngine.clear_load_data_cache
          log = with_captured_log do
            render_crinja(template, vars)
          end
          log.should contain("load_data(\"data/meun.json\") is not a file")
        end
      end
    end

    it "load_data returns nil (empty render) for a malformed JSON data file" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("data")
          File.write("data/bad.json", "{ not valid json ")

          vars = {} of String => Crinja::Value

          # The rescue at the parse site swallows the error into Crinja nil
          # (no exception escapes the build); Crinja renders nil as "none".
          template = "[{{ load_data(path=\"data/bad.json\") }}]"
          result = render_crinja(template, vars)
          result.should eq("[none]")
        end
      end
    end

    it "load_data returns nil (empty render) for an unsupported extension" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("data")
          # File must exist inside project_root to reach the else (unsupported)
          # branch; otherwise the boundary/exists check short-circuits.
          File.write("data/notes.txt", "hello")

          vars = {} of String => Crinja::Value

          template = "[{{ load_data(path=\"data/notes.txt\") }}]"
          result = render_crinja(template, vars)
          # Unsupported extension -> result stays Crinja nil -> renders "none".
          result.should eq("[none]")
        end
      end
    end
  end

  # `get_menu()` reads the `__menus__` global built by `build_global_vars`
  # (see render.cr / Content::Menus.build). These tests inject a minimal
  # `__menus__` shape directly into the render vars so they exercise only the
  # function's own language-resolution logic, not the full menu builder
  # (covered separately by spec/unit/menus_spec.cr).
  describe "get_menu function" do
    it "resolves a named menu for the current page's language" do
      vars = {} of String => Crinja::Value
      vars["page_language"] = Crinja::Value.new("ko")
      vars["_i18n_default_language"] = Crinja::Value.new("en")
      vars["__menus__"] = menus_value({
        "en" => {"main" => ["Home"]},
        "ko" => {"main" => ["홈"]},
      })

      template = "{% for item in get_menu(name=\"main\") %}{{ item.name }}{% endfor %}"
      result = render_crinja(template, vars)
      result.should eq("홈")
    end

    it "falls back to the default language when the current language has no entries for that menu" do
      vars = {} of String => Crinja::Value
      vars["page_language"] = Crinja::Value.new("ko")
      vars["_i18n_default_language"] = Crinja::Value.new("en")
      vars["__menus__"] = menus_value({
        "en" => {"main" => ["Home"]},
        "ko" => {} of String => Array(String),
      })

      template = "{% for item in get_menu(name=\"main\") %}{{ item.name }}{% endfor %}"
      result = render_crinja(template, vars)
      result.should eq("Home")
    end

    it "returns an empty array (not an error) for an unregistered menu name" do
      vars = {} of String => Crinja::Value
      vars["page_language"] = Crinja::Value.new("en")
      vars["_i18n_default_language"] = Crinja::Value.new("en")
      vars["__menus__"] = Crinja::Value.new(menus_value({"en" => {"main" => ["Home"]}}))

      template = "[{% for item in get_menu(name=\"missing\") %}{{ item.name }}{% endfor %}]"
      result = render_crinja(template, vars)
      result.should eq("[]")
    end
  end
end
