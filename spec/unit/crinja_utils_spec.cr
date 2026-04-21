require "../spec_helper"

# =============================================================================
# CrinjaUtils tests
#
# We verify that YAML, TOML, and JSON values converted via CrinjaUtils produce
# the correct output when rendered through a Crinja template.  This is more
# robust than inspecting .raw internals, because it tests the values exactly
# as they will be used in real site builds.
# =============================================================================

private def render(vars : Hash(String, Crinja::Value), template_str : String) : String
  env = Crinja.new
  tpl = env.from_string(template_str)
  tpl.render(vars).strip
end

describe Hwaro::Utils::CrinjaUtils do
  # ---------------------------------------------------------------------------
  # YAML → Crinja::Value
  # ---------------------------------------------------------------------------
  describe ".from_yaml" do
    it "converts a YAML string value" do
      yaml = YAML.parse(%("hello"))
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"val" => result}
      render(vars, "{{ val }}").should eq("hello")
    end

    it "converts a YAML integer value" do
      yaml = YAML.parse("42")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"val" => result}
      render(vars, "{{ val }}").should eq("42")
    end

    it "converts a YAML float value" do
      yaml = YAML.parse("3.14")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"val" => result}
      render(vars, "{{ val }}").should eq("3.14")
    end

    it "converts a YAML boolean true" do
      yaml = YAML.parse("true")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"val" => result}
      render(vars, "{% if val %}YES{% else %}NO{% endif %}").should eq("YES")
    end

    it "converts a YAML boolean false" do
      yaml = YAML.parse("false")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"val" => result}
      render(vars, "{% if val %}YES{% else %}NO{% endif %}").should eq("NO")
    end

    it "converts a YAML null to nil (falsy)" do
      yaml = YAML.parse("null")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"val" => result}
      render(vars, "{% if val %}YES{% else %}NO{% endif %}").should eq("NO")
    end

    it "converts a YAML array" do
      yaml = YAML.parse("[1, 2, 3]")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"items" => result}
      render(vars, "{{ items | length }}").should eq("3")
      render(vars, "{% for i in items %}{{ i }},{% endfor %}").should eq("1,2,3,")
    end

    it "converts a YAML array of strings" do
      yaml = YAML.parse("[\"a\", \"b\", \"c\"]")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"items" => result}
      render(vars, "{% for i in items %}{{ i }},{% endfor %}").should eq("a,b,c,")
    end

    it "converts a YAML hash" do
      yaml = YAML.parse("name: Alice\nage: 30")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"data" => result}
      render(vars, "{{ data.name }}").should eq("Alice")
      render(vars, "{{ data.age }}").should eq("30")
    end

    it "converts nested YAML structures" do
      yaml_str = <<-YAML
        person:
          name: Bob
          hobbies:
            - reading
            - coding
          active: true
        YAML
      yaml = YAML.parse(yaml_str)
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"data" => result}
      render(vars, "{{ data.person.name }}").should eq("Bob")
      render(vars, "{% if data.person.active %}ACTIVE{% endif %}").should eq("ACTIVE")
      render(vars, "{% for h in data.person.hobbies %}{{ h }},{% endfor %}").should eq("reading,coding,")
    end

    it "converts an empty YAML hash" do
      yaml = YAML.parse("{}")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"data" => result}
      # An empty hash is truthy but iterating gives nothing
      render(vars, "{% for k, v in data %}{{ k }}{% endfor %}").should eq("")
    end

    it "converts an empty YAML array" do
      yaml = YAML.parse("[]")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"items" => result}
      render(vars, "{{ items | length }}").should eq("0")
    end

    it "converts mixed-type YAML arrays" do
      yaml = YAML.parse("[\"hello\", 42, true]")
      result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      vars = {"items" => result}
      render(vars, "{{ items | length }}").should eq("3")
      render(vars, "{{ items[0] }}").should eq("hello")
      render(vars, "{{ items[1] }}").should eq("42")
    end
  end

  # ---------------------------------------------------------------------------
  # JSON → Crinja::Value
  # ---------------------------------------------------------------------------
  describe ".from_json" do
    it "converts a JSON string" do
      json = JSON.parse(%("hello"))
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"val" => result}
      render(vars, "{{ val }}").should eq("hello")
    end

    it "converts a JSON integer" do
      json = JSON.parse("42")
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"val" => result}
      render(vars, "{{ val }}").should eq("42")
    end

    it "converts a JSON float" do
      json = JSON.parse("3.14")
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"val" => result}
      render(vars, "{{ val }}").should eq("3.14")
    end

    it "converts a JSON boolean true" do
      json = JSON.parse("true")
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"val" => result}
      render(vars, "{% if val %}YES{% else %}NO{% endif %}").should eq("YES")
    end

    it "converts a JSON boolean false" do
      json = JSON.parse("false")
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"val" => result}
      render(vars, "{% if val %}YES{% else %}NO{% endif %}").should eq("NO")
    end

    it "converts a JSON null" do
      json = JSON.parse("null")
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"val" => result}
      render(vars, "{% if val %}YES{% else %}NO{% endif %}").should eq("NO")
    end

    it "converts a JSON array" do
      json = JSON.parse("[1, 2, 3]")
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"items" => result}
      render(vars, "{{ items | length }}").should eq("3")
      render(vars, "{% for i in items %}{{ i }},{% endfor %}").should eq("1,2,3,")
    end

    it "converts a JSON object" do
      json = JSON.parse(%({"name": "Alice", "age": 30}))
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"data" => result}
      render(vars, "{{ data.name }}").should eq("Alice")
      render(vars, "{{ data.age }}").should eq("30")
    end

    it "converts nested JSON structures" do
      json = JSON.parse(%({"person": {"name": "Bob", "hobbies": ["reading", "coding"], "active": true}}))
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"data" => result}
      render(vars, "{{ data.person.name }}").should eq("Bob")
      render(vars, "{% if data.person.active %}ACTIVE{% endif %}").should eq("ACTIVE")
      render(vars, "{% for h in data.person.hobbies %}{{ h }},{% endfor %}").should eq("reading,coding,")
    end

    it "converts an empty JSON object" do
      json = JSON.parse("{}")
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"data" => result}
      render(vars, "{% for k, v in data %}{{ k }}{% endfor %}").should eq("")
    end

    it "converts an empty JSON array" do
      json = JSON.parse("[]")
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"items" => result}
      render(vars, "{{ items | length }}").should eq("0")
    end

    it "converts a deeply nested JSON structure" do
      json = JSON.parse(%({"a": {"b": {"c": {"d": "deep"}}}}))
      result = Hwaro::Utils::CrinjaUtils.from_json(json)
      vars = {"data" => result}
      render(vars, "{{ data.a.b.c.d }}").should eq("deep")
    end
  end

  # ---------------------------------------------------------------------------
  # TOML → Crinja::Value
  # ---------------------------------------------------------------------------
  describe ".from_toml (Hash)" do
    it "converts a simple TOML hash" do
      toml = TOML.parse("name = \"Alice\"\nage = 30")
      result = Hwaro::Utils::CrinjaUtils.from_toml(toml)
      vars = {"data" => result}
      render(vars, "{{ data.name }}").should eq("Alice")
      render(vars, "{{ data.age }}").should eq("30")
    end

    it "converts a TOML hash with boolean values" do
      toml = TOML.parse("enabled = true\ndisabled = false")
      result = Hwaro::Utils::CrinjaUtils.from_toml(toml)
      vars = {"data" => result}
      render(vars, "{% if data.enabled %}ON{% endif %}").should eq("ON")
      render(vars, "{% if data.disabled %}ON{% else %}OFF{% endif %}").should eq("OFF")
    end

    it "converts a TOML hash with float values" do
      toml = TOML.parse("pi = 3.14")
      result = Hwaro::Utils::CrinjaUtils.from_toml(toml)
      vars = {"data" => result}
      render(vars, "{{ data.pi }}").should eq("3.14")
    end

    it "converts a TOML hash with array values" do
      toml = TOML.parse("tags = [\"crystal\", \"web\"]")
      result = Hwaro::Utils::CrinjaUtils.from_toml(toml)
      vars = {"data" => result}
      render(vars, "{{ data.tags | length }}").should eq("2")
      render(vars, "{% for t in data.tags %}{{ t }},{% endfor %}").should eq("crystal,web,")
    end

    it "converts a nested TOML table" do
      toml_str = <<-TOML
        [server]
        host = "localhost"
        port = 8080
        TOML
      toml = TOML.parse(toml_str)
      result = Hwaro::Utils::CrinjaUtils.from_toml(toml)
      vars = {"data" => result}
      render(vars, "{{ data.server.host }}").should eq("localhost")
      render(vars, "{{ data.server.port }}").should eq("8080")
    end

    it "converts an empty TOML hash" do
      toml = TOML.parse("")
      result = Hwaro::Utils::CrinjaUtils.from_toml(toml)
      vars = {"data" => result}
      render(vars, "{% for k, v in data %}{{ k }}{% endfor %}").should eq("")
    end

    it "converts TOML with array of tables" do
      toml_str = <<-TOML
        [[items]]
        name = "first"

        [[items]]
        name = "second"
        TOML
      toml = TOML.parse(toml_str)
      result = Hwaro::Utils::CrinjaUtils.from_toml(toml)
      vars = {"data" => result}
      render(vars, "{{ data.items | length }}").should eq("2")
      render(vars, "{% for item in data.items %}{{ item.name }},{% endfor %}").should eq("first,second,")
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-format consistency
  # ---------------------------------------------------------------------------
  describe "round-trip consistency" do
    it "JSON and YAML produce the same Crinja output for equivalent data" do
      json = JSON.parse(%({"title": "Hello", "count": 5, "active": true}))
      yaml = YAML.parse("title: Hello\ncount: 5\nactive: true")

      json_result = Hwaro::Utils::CrinjaUtils.from_json(json)
      yaml_result = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)

      tpl = "{{ data.title }}|{{ data.count }}|{% if data.active %}YES{% endif %}"
      render({"data" => json_result}, tpl).should eq(render({"data" => yaml_result}, tpl))
    end

    it "JSON and TOML produce the same Crinja output for equivalent data" do
      json = JSON.parse(%({"title": "Hello", "count": 5, "active": true}))
      toml = TOML.parse("title = \"Hello\"\ncount = 5\nactive = true")

      json_result = Hwaro::Utils::CrinjaUtils.from_json(json)
      toml_result = Hwaro::Utils::CrinjaUtils.from_toml(toml)

      tpl = "{{ data.title }}|{{ data.count }}|{% if data.active %}YES{% endif %}"
      render({"data" => json_result}, tpl).should eq(render({"data" => toml_result}, tpl))
    end

    it "all three formats produce the same output for arrays" do
      json = JSON.parse(%({"items": ["a", "b", "c"]}))
      yaml = YAML.parse("items:\n  - a\n  - b\n  - c")
      toml = TOML.parse("items = [\"a\", \"b\", \"c\"]")

      json_r = Hwaro::Utils::CrinjaUtils.from_json(json)
      yaml_r = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      toml_r = Hwaro::Utils::CrinjaUtils.from_toml(toml)

      tpl = "{% for i in data.items %}{{ i }},{% endfor %}"
      expected = render({"data" => json_r}, tpl)
      render({"data" => yaml_r}, tpl).should eq(expected)
      render({"data" => toml_r}, tpl).should eq(expected)
    end

    it "all three formats produce the same output for nested objects" do
      json = JSON.parse(%({"server": {"host": "localhost", "port": 8080}}))
      yaml = YAML.parse("server:\n  host: localhost\n  port: 8080")
      toml = TOML.parse("[server]\nhost = \"localhost\"\nport = 8080")

      json_r = Hwaro::Utils::CrinjaUtils.from_json(json)
      yaml_r = Hwaro::Utils::CrinjaUtils.from_yaml(yaml)
      toml_r = Hwaro::Utils::CrinjaUtils.from_toml(toml)

      tpl = "{{ data.server.host }}:{{ data.server.port }}"
      expected = render({"data" => json_r}, tpl)
      expected.should eq("localhost:8080")
      render({"data" => yaml_r}, tpl).should eq(expected)
      render({"data" => toml_r}, tpl).should eq(expected)
    end
  end
end
