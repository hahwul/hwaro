# Crinja patches that keep a template error LOCATED (file:line:col + excerpt).
#
# Two upstream gaps threw away the location for whole classes of failures:
#
#   1. A plain Crystal exception raised inside a filter, test or function
#      (`{{ [1, 2] | slice(0) }}` → `Division by 0`, `{{ [] | random }}` →
#      `Can't sample empty collection`, any custom filter that trips on its
#      input) is not a `Crinja::Error`, so `Evaluator`'s per-node rescue never
#      attaches the node, hwaro's `rescue ex : Crinja::Error` sites never see
#      it, and the build dies with `Render failed ...: Division by 0` and no
#      template name or line.
#
#   2. A template whose FIRST character is a newline reported every location
#      one line early (`templates/page.html:1:2` for a tag on line 2, caret
#      painted on a phantom line). `CharacterStream` counts a newline when the
#      reader ARRIVES at it, and the first character is never arrived at.
#
# Patch order matters for nothing here; both are independent of the other
# Crinja patches under src/ext/.
require "crinja"

# === 1. Non-Crinja exceptions inside filters/tests/functions get a node ====
#
# Wrap at the three evaluator visitors that invoke user/builtin code. The
# wrapped error is a `Crinja::RuntimeError`, so the surrounding `visit`
# rescue (which only knows `Crinja::Error`) attaches the expression's
# location exactly as it does for Crinja's own errors, and every hwaro
# rescue site classifies it as HWARO_E_TEMPLATE with the source excerpt.
# Crinja errors pass through untouched — an inner wrap must not be re-wrapped
# by an outer filter expression.
class Crinja::Evaluator
  def evaluate(expression : AST::FilterExpression)
    previous_def
  rescue ex : Crinja::Error
    raise ex
  rescue ex : Exception
    raise Crinja::RuntimeError.new("#{ex.message} (#{ex.class})", cause: ex).at(expression)
  end

  def evaluate(expression : AST::TestExpression)
    previous_def
  rescue ex : Crinja::Error
    raise ex
  rescue ex : Exception
    raise Crinja::RuntimeError.new("#{ex.message} (#{ex.class})", cause: ex).at(expression)
  end

  def evaluate(expression : AST::CallExpression)
    previous_def
  rescue ex : Crinja::Error
    raise ex
  rescue ex : Exception
    raise Crinja::RuntimeError.new("#{ex.message} (#{ex.class})", cause: ex).at(expression)
  end
end

# === 2. A leading newline is a line break too ==============================
#
# `next_char` bumps `line` when the character it moves ONTO is a newline, so
# the position reported while sitting on a newline is already "next line,
# column 0". The very first character is never moved onto — the reader starts
# there — so a template beginning with "\n" left the counter on line 1 and
# every later token one line short. Seed the position the same way
# `next_char` would have.
class Crinja::Parser::CharacterStream
  def initialize(string)
    @reader = Char::Reader.new(string)
    @position = initial_position
  end

  def rewind
    @reader.pos = 0
    @position = initial_position
  end

  private def initial_position : StreamPosition
    if @reader.has_next? && @reader.current_char == '\n'
      StreamPosition.new(2, 0, 0)
    else
      StreamPosition.new
    end
  end
end
