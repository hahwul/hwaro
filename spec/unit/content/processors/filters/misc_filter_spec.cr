require "../../../../support/build_helper"
require "../../../../support/template_helper"

# `tojson` / `jsonify` on a non-finite float. `nan` and `inf` are valid TOML
# and YAML values, JSON has no spelling for them, and `Float64#to_json`
# raised — so one `ratio = nan` in front matter aborted the build as a
# template error from any `{{ page | tojson }}`.
describe "tojson and jsonify with non-finite floats" do
  it "writes null for nan and infinities" do
    vars = {
      "n"  => Crinja::Value.new(Float64::NAN),
      "l"  => Crinja::Value.new([Crinja::Value.new(Float64::INFINITY), Crinja::Value.new(-Float64::INFINITY), Crinja::Value.new(1.5)]),
      "ok" => Crinja::Value.new(0.25),
    }
    render_crinja("{{ n | tojson }}|{{ l | tojson }}|{{ ok | tojson }}", vars).should eq("null|[null,null,1.5]|0.25")
    render_crinja("{{ n | jsonify }}|{{ l | jsonify }}", vars).should eq("null|[null,null,1.5]")
  end

  it "builds a page whose front matter holds nan or inf" do
    build_site(
      %(title = "t"\nbase_url = "https://example.com"\n),
      content_files: {"p.md" => "+++\ntitle = \"p\"\n[extra]\nratio = nan\nmax = inf\nok = 2.5\n+++\nbody\n"},
      template_files: {"page.html" => "{{ page.extra | tojson }}"},
    ) do
      File.read("public/p/index.html").should eq(%({"ratio":null,"max":null,"ok":2.5}))
    end
  end
end
