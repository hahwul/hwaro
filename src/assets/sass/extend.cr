# @extend support: selector-level extension applied as a post-pass over
# the flat CSS tree, plus %placeholder scrubbing.
#
# Subset semantics (documented in features/sass.md):
# - Targets must be simple selectors (`.class`, `%placeholder`, `#id`,
#   `tag`, `:pseudo`); a compound or complex target never matches.
# - Extension removes the target from its compound and unifies the
#   extender's final compound with what remains; the extender's ancestor
#   compounds are prepended after the extended selector's own prefix.
#   dart-sass additionally "weaves" both prefix orders — hwaro emits the
#   first order only.
# - Extends apply document-wide. dart-sass scopes them per module and
#   forbids crossing @media boundaries; hand-written stylesheets don't
#   hit the difference, and erring on the side of applying keeps the
#   extended styles present rather than silently absent.
#
# Selector text here is fully resolved output text (interpolation and `&`
# already substituted), so parsing is a light tokenization — compounds
# split on combinators/whitespace, simple selectors split on sigils —
# with quotes, attribute brackets, and pseudo-class parens consumed as
# units.

require "./css"
require "./parser"

module Hwaro
  module Assets
    module Sass
      module Extend
        extend self

        # One `@extend` directive: the extending rule's resolved selectors,
        # one target selector, and the location for error reporting.
        record Request, extenders : Array(String), target : String,
          optional : Bool, path : String, line : Int32, column : Int32

        # One parsed piece of a complex selector.
        record Compound, simples : Array(String)
        record Combinator, text : String
        alias Item = Compound | Combinator

        # nil when `selector` does not contain `target` as a complete
        # simple selector; otherwise every extension of `selector` by
        # `extenders` (possibly empty when no extender unifies — the
        # target still counts as found).
        def extend_selector(selector : String, target : String,
                            extenders : Array(String)) : Array(String)?
          items = parse_items(selector)
          return unless items
          found = false
          results = [] of String
          items.each_with_index do |item, idx|
            next unless item.is_a?(Compound)
            if slot = item.simples.index(target)
              found = true
              rest = item.simples.dup
              rest.delete_at(slot)
              extenders.each do |ext_sel|
                ext_items = parse_items(ext_sel)
                next unless ext_items
                last = ext_items.last?
                next unless last.is_a?(Compound)
                merged = unify_compound(last.simples, rest)
                next unless merged
                prefix = merge_prefixes(items[0...idx], ext_items[0...-1])
                new_items = prefix + [Compound.new(merged).as(Item)] + items[idx + 1..]
                results << serialize_items(new_items)
              end
            end
            # A target inside a selector pseudo-class argument
            # (`:is(.b)`, `:not(.b)`) extends the argument list itself:
            # `:is(.b)` extended by `.c` → `:is(.b, .c)` (dart-sass
            # semantics for selector pseudos).
            item.simples.each_with_index do |simple, si|
              extended = extend_pseudo_args(simple, target, extenders)
              next unless extended
              found = true
              next if extended == simple
              new_simples = item.simples.dup
              new_simples[si] = extended
              new_items = items.dup
              new_items[idx] = Compound.new(new_simples)
              results << serialize_items(new_items)
            end
          end
          found ? results : nil
        end

        # nil when `simple` is not a pseudo whose argument list contains
        # the target; otherwise the pseudo with every extension appended
        # to its argument list (unchanged text when nothing unified).
        private def extend_pseudo_args(simple : String, target : String,
                                       extenders : Array(String)) : String?
          return unless simple.starts_with?(':')
          open = simple.index('(')
          return unless open && simple.ends_with?(')')
          inner = simple[(open + 1)...-1]
          args = Parser.split_top_level_commas(inner).map(&.strip).reject(&.empty?)
          found = false
          additions = [] of String
          args.each do |arg|
            results = extend_selector(arg, target, extenders)
            next unless results
            found = true
            results.each do |sel|
              additions << sel unless args.includes?(sel) || additions.includes?(sel)
            end
          end
          return unless found
          simple[0..open] + (args + additions).join(", ") + ")"
        end

        # Combines the extended selector's prefix with the extender's
        # ancestors. When one is a leading subsequence of the other they
        # merge instead of concatenating — extending `%p` in `.nav %p`
        # by `.nav > .c` must yield `.nav > .c`, not `.nav .nav > .c`
        # (the head of dart-sass's prefix weave).
        private def merge_prefixes(own : Array(Item), ext : Array(Item)) : Array(Item)
          if leading?(own, ext)
            ext
          elsif leading?(ext, own)
            own
          else
            own + ext
          end
        end

        private def leading?(head : Array(Item), full : Array(Item)) : Bool
          head.size <= full.size && full[0...head.size] == head
        end

        # Merges the extender's final compound with what remains of the
        # extended compound: element selector first, then the other simple
        # selectors, pseudo-classes/-elements last. nil when the two need
        # different element selectors (`div` vs `span` can't both match).
        def unify_compound(ext : Array(String), rest : Array(String)) : Array(String)?
          ext_elem = ext.find { |s| element?(s) }
          rest_elem = rest.find { |s| element?(s) }
          if ext_elem && rest_elem && ext_elem != rest_elem
            return unless ext_elem == "*" || rest_elem == "*"
          end
          elem =
            if ext_elem && rest_elem
              ext_elem == "*" ? rest_elem : ext_elem
            else
              ext_elem || rest_elem
            end
          merged = [] of String
          merged << elem if elem
          (ext + rest).each do |s|
            next if element?(s) || pseudo?(s)
            merged << s unless merged.includes?(s)
          end
          (ext + rest).each do |s|
            next unless pseudo?(s)
            merged << s unless merged.includes?(s)
          end
          merged
        end

        # True when the selector references a `%placeholder` outside
        # quotes and attribute brackets — such selectors never reach the
        # output (dart-sass emits nothing for un-extended placeholders).
        def placeholder?(selector : String) : Bool
          chars = selector.chars
          i = 0
          while i < chars.size
            case chars[i]
            when '\\'
              # An escaped character is literal — `.sale\%-badge` is a
              # plain CSS class, not a placeholder.
              i += 2
            when '"', '\''
              j = skip_string(chars, i)
              return false unless j
              i = j
            when '['
              j = skip_bracket(chars, i)
              return false unless j
              i = j
            when '%'
              n = chars[i + 1]?
              return true if n && (n.ascii_letter? || n == '_' || n == '-' || n.ord > 0x7F)
              i += 1
            else
              i += 1
            end
          end
          false
        end

        # Removes placeholder selectors from every rule (recursively,
        # skipping @keyframes bodies) and drops rules with none left.
        def scrub_placeholders(nodes : Array(Css::Node)) : Nil
          nodes.reject! do |node|
            case node
            when Css::Rule
              node.selectors.reject! { |s| placeholder?(s) }
              node.selectors.empty?
            when Css::AtRule
              scrub_placeholders(node.children) unless keyframes_name?(node.name)
              false
            else
              false
            end
          end
        end

        def keyframes_name?(name : String) : Bool
          name == "keyframes" || name.ends_with?("-keyframes")
        end

        # Parses a complex selector into compounds and combinators; nil
        # when the text is too exotic to model (unbalanced quotes/spans).
        def parse_items(selector : String) : Array(Item)?
          items = [] of Item
          chars = selector.chars
          i = 0
          while i < chars.size
            c = chars[i]
            if c.ascii_whitespace?
              i += 1
            elsif c == '>' || c == '+' || c == '~'
              items << Combinator.new(c.to_s)
              i += 1
            else
              stop = scan_compound(chars, i)
              return if stop.nil? || stop <= i
              simples = split_compound(selector[i...stop])
              return unless simples
              items << Compound.new(simples)
              i = stop
            end
          end
          items
        end

        # Advances past one compound selector (stops at whitespace or a
        # top-level combinator); nil on an unbalanced span.
        private def scan_compound(chars : Array(Char), start : Int32) : Int32?
          i = start
          while i < chars.size
            c = chars[i]
            break if c.ascii_whitespace? || c == '>' || c == '+' || c == '~'
            case c
            when '['
              j = skip_bracket(chars, i)
              return unless j
              i = j
            when '('
              j = skip_paren(chars, i)
              return unless j
              i = j
            when '"', '\''
              return # a bare string is not a selector we model
            else
              i += 1
            end
          end
          i
        end

        # Splits one compound into simple selectors (`.a:hover::before` →
        # [".a", ":hover", "::before"]).
        private def split_compound(text : String) : Array(String)?
          simples = [] of String
          chars = text.chars
          i = 0
          start = 0
          while i < chars.size
            case c = chars[i]
            when '['
              j = skip_bracket(chars, i)
              return unless j
              if i > start
                simples << text[start...i]
              end
              simples << text[i...j]
              start = j
              i = j
            when '('
              j = skip_paren(chars, i)
              return unless j
              i = j
            when '.', '#', '%', ':', '&'
              # The second colon of `::element` continues the previous
              # simple selector instead of starting a new one.
              if i > start && !(c == ':' && chars[i - 1] == ':')
                simples << text[start...i]
                start = i
              end
              i += 1
            else
              i += 1
            end
          end
          simples << text[start...chars.size] if start < chars.size
          simples
        end

        private def serialize_items(items : Array(Item)) : String
          items.join(" ") do |item|
            case item
            in Compound   then item.simples.join
            in Combinator then item.text
            end
          end
        end

        private def element?(simple : String) : Bool
          first = simple[0]?
          return false unless first
          first != '.' && first != '#' && first != '%' && first != ':' &&
            first != '[' && first != '&'
        end

        private def pseudo?(simple : String) : Bool
          simple.starts_with?(':')
        end

        private def skip_string(chars : Array(Char), start : Int32) : Int32?
          quote = chars[start]
          i = start + 1
          while i < chars.size
            c = chars[i]
            if c == '\\'
              i += 2
            elsif c == quote
              return i + 1
            else
              i += 1
            end
          end
          nil
        end

        private def skip_bracket(chars : Array(Char), start : Int32) : Int32?
          i = start + 1
          while i < chars.size
            case chars[i]
            when '"', '\''
              j = skip_string(chars, i)
              return unless j
              i = j
            when ']'
              return i + 1
            else
              i += 1
            end
          end
          nil
        end

        private def skip_paren(chars : Array(Char), start : Int32) : Int32?
          depth = 0
          i = start
          while i < chars.size
            case chars[i]
            when '"', '\''
              j = skip_string(chars, i)
              return unless j
              i = j
            when '('
              depth += 1
              i += 1
            when ')'
              depth -= 1
              i += 1
              return i if depth == 0
            else
              i += 1
            end
          end
          nil
        end
      end
    end
  end
end
