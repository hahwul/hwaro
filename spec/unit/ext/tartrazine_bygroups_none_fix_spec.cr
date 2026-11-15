require "../../spec_helper"

# ext/tartrazine_bygroups_none_fix.cr — a bare `None` in <bygroups> skips a group.
describe "Tartrazine bygroups None placeholder (ext/tartrazine_bygroups_none_fix)" do
  it "keeps Liquid tag text intact" do
    [
      "{% if a %}y{% endif %}",
      "{% for i in b %}{% endfor %}",
      "{% unless a %}z{% endunless %}",
      "{% case a %}{% when 1 %}one{% endcase %}",
      "{% highlight ruby %}x{% endhighlight %}",
      "{% comment %}c{% endcomment %}",
      "{% if a == b %}1{% endif %}",
      "{% if a != b %}1{% elsif a >= 2 %}2{% else %}3{% endif %}",
    ].each do |source|
      tokens = Tartrazine.lexer("liquid").tokenizer(source).to_a
      tokens.map(&.[:value]).join.should eq(source)
    end
  end

  # Ruby's whitespace-delimited percent literal: bygroups(Text, String.Other,
  # None), the None group nested inside the string group.
  it "keeps a whitespace-delimited Ruby percent literal intact" do
    ["% x  y\n", "b = %\tq\t\n", "x >%\tab\n\tc\n"].each do |source|
      tokens = Tartrazine.lexer("ruby").tokenizer(source).to_a
      tokens.map(&.[:value]).join.should eq(source)
    end
  end

  it "emits the closing %} as punctuation" do
    tokens = Tartrazine.lexer("liquid").tokenizer("{% if a %}y{% endif %}").to_a
    tokens.last.should eq({type: "Punctuation", value: "%}"})
  end
end
