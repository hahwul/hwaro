require "../../spec_helper"

private def render_test(source : String) : String
  users = [{"name" => "Bob", "age" => 30}, {"name" => "alice", "age" => 25}, {"name" => "Carl", "age" => 31}]
  Crinja.new.from_string(source).render({"users" => Crinja.value(users), "l" => Crinja.value([3, 1, 2])})
end

# Expected strings are Jinja2 3.1's output for the same source (Crinja
# prints booleans in lowercase).
describe "Crinja comparison tests" do
  it "supports the operator names and symbols in select/selectattr" do
    render_test("{{ users | selectattr('age', '>', 26) | map(attribute='name') | join(',') }}").should eq("Bob,Carl")
    render_test("{{ users | rejectattr('age', 'ge', 30) | map(attribute='name') | join(',') }}").should eq("alice")
    render_test("{{ l | select('<', 3) | list }}|{{ l | select('le', 2) | list }}|{{ l | reject('ne', 2) | list }}")
      .should eq("[1, 2]|[1, 2]|[2]")
  end

  it "compares floats and strings instead of their integer parts" do
    render_test("{{ 2.5 is greaterthan 2 }}{{ 'b' is gt 'a' }}{{ 1.5 is lessthan 2 }}{{ 3 is le 2 }}")
      .should eq("truetruetruefalse")
  end

  it "keeps equalto" do
    render_test("{{ users | selectattr('name', 'equalto', 'Bob') | list | length }}{{ 'a' is eq 'a' }}").should eq("1true")
  end
end
