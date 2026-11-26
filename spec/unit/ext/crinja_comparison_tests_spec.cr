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

  it "compares a string with a number or an array in either operand order" do
    render_test("{{ 'a' > 1 }}{{ 1 < 'a' }}{{ [1] < 'a' }}{{ 'a' > [1] }}|{{ ['a', 1] | sort | join(',') }}|{{ [1, 'a'] | sort | join(',') }}")
      .should eq("truetruetruetrue|1,a|1,a")
    expect_raises(Crinja::TypeError) { render_test("{{ [1] < 2 }}") }
  end

  it "keeps equalto" do
    render_test("{{ users | selectattr('name', 'equalto', 'Bob') | list | length }}{{ 'a' is eq 'a' }}").should eq("1true")
  end
end

describe "Crinja number tests" do
  # Both sides went through Int32: a larger integer raised "Arithmetic
  # overflow" and a float was truncated (`2.5 is even` was true).
  it "tests an integer past Int32 without overflowing" do
    render_test("{{ 12345678901234567 is even }}|{{ 12345678901234567 is odd }}|{{ 12345678901234567 is divisibleby(3) }}")
      .should eq("false|true|false")
    render_test("{{ 3000000000 is divisibleby 1000 }}").should eq("true")
  end

  it "tests a float as a float" do
    render_test("{{ 2.5 is even }}|{{ 2.5 is odd }}|{{ 4.0 is even }}|{{ 3.0 is odd }}|{{ -2.5 is odd }}")
      .should eq("false|false|true|true|false")
    render_test("{{ 3.5 is divisibleby(3) }}|{{ 7.5 is divisibleby(2.5) }}|{{ 9 is divisibleby(2.5) }}").should eq("false|true|false")
  end

  it "keeps integers, numeric strings and the zero divisor as they were" do
    render_test("{{ -3 is odd }}|{{ 9 is divisibleby 3 }}|{{ '42' is even }}|{{ l | select('odd') | join(',') }}").should eq("true|true|true|3,1")
    expect_raises(Crinja::RuntimeError, /Division by 0/) { render_test("{{ 1 is divisibleby(0) }}") }
  end
end

describe "Crinja lower / upper tests" do
  # Every character had to be a letter of that case, so a space made
  # "hello world" not lower, and "" was both.
  it "reads only the cased characters, as Python's islower/isupper" do
    render_test("{{ 'hello world' is lower }}|{{ 'a-b 1' is lower }}|{{ 'ß straße' is lower }}|{{ 'Hello' is lower }}|{{ '' is lower }}|{{ '12' is lower }}")
      .should eq("true|true|true|false|false|false")
    render_test("{{ 'HELLO WORLD!' is upper }}|{{ 'A1' is upper }}|{{ 'HeLLO' is upper }}|{{ '' is upper }}|{{ 'ǅ' is upper }}|{{ 'ǅ' is lower }}")
      .should eq("true|true|false|false|false|false")
  end
end
