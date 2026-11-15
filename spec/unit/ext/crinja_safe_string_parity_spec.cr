require "../../spec_helper"

# Under `[templates] autoescape` (the 1.0 default) the HTML hwaro renders
# reaches templates as a `Crinja::SafeString` where 0.x handed them a String.
# A SafeString must behave as the equal String everywhere a template can touch
# it: no raise where the String works, and the same text — except where the
# Markup rules deliberately differ (ALLOWED below).

private TEXT = "Ab<c>&'d é b"

private def parity_targets : Array({String, Crinja::Value})
  [
    {"plain", Crinja::Value.new(TEXT)},
    {"safe", Crinja::Value.new(Crinja::SafeString.new(TEXT))},
    {"marked", Crinja::Value.new(Crinja::SafeString.new(TEXT, false, true))},
  ]
end

# Plausible positional argument tuples; a filter rejects most of them, which
# is fine — the outcome must only agree across the three targets.
private ARG_TUPLES = [
  [] of Crinja::Value,
  [Crinja::Value.new(1)],
  [Crinja::Value.new(3)],
  [Crinja::Value.new(2), Crinja::Value.new(true)],
  [Crinja::Value.new("b")],
  [Crinja::Value.new("b"), Crinja::Value.new("X")],
  [Crinja::Value.new(", ")],
  [Crinja::Value.new("%s")],
]

# name => reason. A text difference between the String and a SafeString
# target is accepted only for these (the raise/no-raise outcome must still
# agree); EITHER_MODE ones in both settings, the rest only with the switch on.
private ALLOWED_FILTERS = {
  "e"      => "| e on an unmarked safe value is a no-op (Jinja2); on a marked one (HTML hwaro rendered) it escapes, as on a String",
  "escape" => "same as e",
  "urlize" => "with escaping active a plain value is escaped before linking; a safe one is linked as written (Jinja2)",
  "random" => "nondeterministic",
}

private EITHER_MODE = %w[e escape]

private ALLOWED_TESTS = {
  "escaped" => "a SafeString is escaped by definition; content is one under the default (0.x: a String, so false)",
}

# Constructs a template applies to strings, rendered as text (so printing
# does not differ by type) with the switch on, and with it off.
private CONSTRUCTS = [
  "{{ x ~ 'z' }}", "{{ 'z' ~ x }}", "{{ x + 'z' }}", "{{ x * 2 }}", "{{ x == y }}", "{{ y == x }}", "{{ x != y }}",
  "{{ x < 'z' }}", "{{ 'b' in x }}", "{{ x in [y] }}", "{{ x in {y: 1} }}", "{{ 'q' not in x }}",
  "{{ x[0] }}", "{{ x[1:3] }}", "{{ x[-1] }}", "{% for ch in x %}{{ ch }},{% endfor %}", "{{ x | length }}",
  "{% if x %}T{% else %}F{% endif %}", "{% if e %}T{% else %}F{% endif %}",
  "{{ x is string }}", "{{ x is iterable }}", "{{ x is sequence }}", "{{ x is mapping }}", "{{ x is defined }}", "{{ x is none }}",
  "{{ x | default('d') }}", "{{ e | default('d') }}", "{{ e | default('d', true) }}", "{{ x | tojson }}", "{{ x | jsonify }}",
  "{% set d = {x: 1} %}{{ d[y] }}|{{ d[x] }}", "{% set d = {y: 1} %}{{ d[x] }}|{{ x in d }}",
  "{% set d = {x: 1, 'a': 0, 'b': 0, 'c': 0, 'd': 0, 'e': 0, 'f': 0, 'g': 0, 'h': 0} %}{{ d[y] }}|{{ y in d }}",
  "{% set d = {y: 1, 'a': 0, 'b': 0, 'c': 0, 'd': 0, 'e': 0, 'f': 0, 'g': 0, 'h': 0} %}{{ d[x] }}|{{ x in d }}",
  "{% if x == y %}eq{% endif %}{% if y == x %}qe{% endif %}{% if x != y %}ne{% endif %}", "{{ [x, y, 'a'] | sort | join('|') }}", "{{ [x, y] | unique | length }}",
  "{% for g in [{'k': x}, {'k': y}] | groupby('k') %}{{ g.grouper }}:{{ g.list | length }};{% endfor %}",
  "{% for i in [1, 2] %}{{ loop.cycle(x, 'o') }}{% endfor %}", "{% set s = x %}{{ s }}",
  "{% macro m(v) %}[{{ v }}]{% endmacro %}{{ m(x) }}", "{{ x | first }}", "{{ x | last }}", "{{ x | list | length }}",
  "{{ x | reverse }}", "{{ x | wordcount }}", "{{ x | upper }}", "{{ x.upper() }}", "{{ x | slice(2) | list | length }}",
  "{{ x | batch(3) | list | length }}", "{{ x | map('upper') | join }}", "{{ x | select | list | length }}",
  "{{ x | sum(start='') }}", "{{ x | min }}", "{{ x | max }}", "{{ x | center(20) }}", "{{ x | title }}",
  "{{ x | split(' ') | join('/') }}", "{{ x | striptags }}", "{{ x | wordwrap(5) }}",
]

private def outcome(&) : String
  "ok:" + yield
rescue
  "raise"
end

describe "SafeString parity" do
  [true, false].each do |ae|
    it "every filter treats a SafeString as the equal String (autoescape #{ae})" do
      env = Hwaro::Content::Processors::TemplateEngine.new(ae).env
      env.context.autoescape = ae
      gaps = [] of String
      env.filters.keys.sort!.each do |name|
        ARG_TUPLES.each do |args|
          results = parity_targets.map do |label, target|
            {label, outcome { env.call_filter(name, target, args).to_s }}
          end
          base = results[0][1]
          results[1..].each do |label, got|
            next if got == base
            allowed = ALLOWED_FILTERS.has_key?(name) && (ae || EITHER_MODE.includes?(name))
            next if allowed && got.starts_with?("ok:") == base.starts_with?("ok:")
            gaps << "#{name}(#{args.map(&.to_s).join(", ")}) #{label}: #{got[0, 80]} vs plain #{base[0, 80]}"
          end
        end
      end
      gaps.should eq([] of String)
    end

    it "every test treats a SafeString as the equal String (autoescape #{ae})" do
      env = Hwaro::Content::Processors::TemplateEngine.new(ae).env
      gaps = [] of String
      env.tests.keys.sort!.each do |name|
        ARG_TUPLES.each do |args|
          results = parity_targets.map do |label, target|
            {label, outcome { env.execute_call(env.tests[name], args, target: target).truthy?.to_s }}
          end
          base = results[0][1]
          results[1..].each do |label, got|
            next if got == base || ALLOWED_TESTS.has_key?(name)
            gaps << "is #{name}(#{args.map(&.to_s).join(", ")}) #{label}: #{got} vs plain #{base}"
          end
        end
      end
      gaps.should eq([] of String)
    end
  end

  [true, false].each do |ae|
    it "every string construct treats a SafeString as the equal String (autoescape #{ae})" do
      env = Hwaro::Content::Processors::TemplateEngine.new(ae).env
      gaps = [] of String
      CONSTRUCTS.each do |src|
        results = parity_targets.map do |label, target|
          empty = target.raw.is_a?(Crinja::SafeString) ? Crinja::Value.new(Crinja::SafeString.new("")) : Crinja::Value.new("")
          # `y` is always the plain String: mixed comparisons and lookups
          vars = {"x" => target, "y" => Crinja::Value.new(TEXT), "e" => empty} of String => Crinja::Value
          text = outcome { env.from_string(src).render_text(vars) }
          # an HTML render must not raise where the String works either
          html = outcome { env.from_string(src).render(vars) }.starts_with?("ok:")
          {label, text, html}
        end
        base = results[0]
        results[1..].each do |label, text, html|
          gaps << "#{src} #{label}: #{text[0, 60]} vs plain #{base[1][0, 60]}" unless text == base[1]
          gaps << "#{src} #{label}: HTML render raises" if base[2] && !html
        end
      end
      gaps.should eq([] of String)
    end
  end
end

describe "SafeString hashing" do
  it "hashes from the string alone, so equal values find each other as keys" do
    marked = Crinja::SafeString.new(TEXT, false, true)
    unmarked = Crinja::SafeString.new(TEXT)
    marked.hash.should eq(unmarked.hash)
    marked.hash.should eq(TEXT.hash)
    env = Hwaro::Content::Processors::TemplateEngine.new.env
    filler = "'a': 0, 'b': 0, 'c': 0, 'd': 0, 'e': 0, 'f': 0, 'g': 0, 'h': 0"
    vars = {"m" => Crinja::Value.new(marked), "u" => Crinja::Value.new(unmarked), "p" => Crinja::Value.new(TEXT)} of String => Crinja::Value
    [{"m", "u"}, {"u", "m"}, {"m", "p"}, {"p", "m"}, {"u", "p"}, {"p", "u"}].each do |key, lookup|
      src = "{% set d = {#{key}: 1, #{filler}} %}{{ #{lookup} in d }}|{{ d[#{lookup}] }}"
      env.from_string(src).render(vars).should eq("true|1"), "#{key} -> #{lookup}"
    end
  end
end
