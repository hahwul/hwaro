require "../../spec_helper"

private def render_loop(source : String) : String
  Crinja.new.from_string(source).render({"l" => Crinja::Value.new([3, 1, 2, 5].map { |i| Crinja::Value.new(i) })})
end

# Expected strings are Jinja2 3.1's output for the same source (Crinja
# prints booleans in lowercase).
describe "Crinja `loop` variable" do
  it "counts a filtered loop's items" do
    render_loop("{% for i in l if i > 1 %}{{ loop.index }}/{{ loop.length }}/{{ loop.revindex }}/{{ loop.revindex0 }} {% endfor %}")
      .should eq("1/3/3/2 2/3/2/1 3/3/1/0 ")
    render_loop("{% for i in l if i > 1 %}{{ loop.length }}{{ i }},{% endfor %}").should eq("33,32,35,")
  end

  it "keeps a filtered loop's item variables out of the enclosing scope" do
    render_loop("{% for i in l if i > 1 %}{% endfor %}[{{ i }}]").should eq("[]")
    render_loop("{% set i = 'outer' %}{% for i in l if i > 2 %}{{ i }}{% endfor %}{{ i }}").should eq("35outer")
  end

  it "exposes previtem and nextitem" do
    render_loop("{% for i in l %}{{ loop.previtem }}:{{ loop.nextitem }} {% endfor %}").should eq(":1 3:2 1:5 2: ")
    render_loop("{% for i in l if i > 1 %}{{ loop.previtem }}:{{ loop.nextitem }} {% endfor %}").should eq(":2 3:5 2: ")
  end

  it "supports loop.changed" do
    render_loop("{% for i in [1,1,2,2,1] %}{% if loop.changed(i) %}{{ i }}{% endif %}{% endfor %}").should eq("121")
  end

  it "reports depth for plain and recursive loops" do
    render_loop("{% for i in l %}{{ loop.depth }}{{ loop.depth0 }}{% endfor %}").should eq("10101010")
    render_loop("{% for i in [[1,[2]],[3]] recursive %}{{ loop.depth }}{% if i is iterable %}{{ loop(i) }}{% endif %}{% endfor %}")
      .should eq("122312")
  end
end
