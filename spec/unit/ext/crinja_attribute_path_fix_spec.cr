require "../../spec_helper"

private def render_attr(source : String) : String
  users = [
    {"name" => "Bob", "extra" => {"featured" => true, "weight" => 2, "rank" => 1}, "tags" => ["a", "b"]},
    {"name" => "alice", "extra" => {"featured" => false, "weight" => 1, "rank" => 2}, "tags" => ["c"]},
    {"name" => "Carl", "extra" => {"featured" => true, "weight" => 3, "rank" => 1}, "tags" => [] of String},
  ]
  Crinja.new.from_string(source).render({"users" => Crinja.value(users)})
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja dotted attribute paths in filters" do
  it "selects and rejects on a nested attribute" do
    render_attr("{{ users | selectattr('extra.featured') | map(attribute='name') | join(',') }}").should eq("Bob,Carl")
    render_attr("{{ users | rejectattr('extra.featured') | map(attribute='name') | join(',') }}").should eq("alice")
    render_attr("{{ users | selectattr('extra.weight', 'equalto', 2) | map(attribute='name') | join }}").should eq("Bob")
  end

  it "maps and joins a nested attribute or index" do
    render_attr("{{ users | map(attribute='extra.weight') | join }}").should eq("213")
    render_attr("{{ users | map(attribute='tags.0') | join(',') }}").should eq("a,c,")
    render_attr("{{ users | join(',', attribute='extra.weight') }}").should eq("2,1,3")
  end

  it "maps a missing attribute to `default`" do
    render_attr("{{ users | map(attribute='nope', default='?') | join }}").should eq("???")
  end

  it "sorts on nested and multiple attributes" do
    render_attr("{{ users | sort(attribute='extra.weight', reverse=true) | map(attribute='name') | join(',') }}")
      .should eq("Carl,Bob,alice")
    render_attr("{{ users | sort(attribute='extra.rank,name') | map(attribute='name') | join(',') }}")
      .should eq("Bob,Carl,alice")
  end

  it "keeps equal items in order when sorting in reverse" do
    render_attr("{{ ['b', 'A', 'c', 'a'] | sort(reverse=true) }}").should eq("['c', 'b', 'A', 'a']")
  end
end
