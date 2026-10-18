# Monkey-patch for Tartrazine's lexer lookup by name, kept here so we don't
# fork the vendored library, like ext/tartrazine_mt_fix.cr.
#
# Two common fence languages fell back to plain, unhighlighted output:
#
# - `cr`: LEXERS_BY_NAME maps it to the "crystal" XML file, but Crystal has
#   no XML lexer. It is the hand-written CrystalLexer, which `lexer_by_name`
#   only returns for the exact name "crystal", so `cr` raised "Unknown lexer".
# - `yml`: not in LEXERS_BY_NAME at all (only `*.yml` as a filename).
#
# Both are documented fence identifiers (and Highlight.js aliases), so map
# them onto the canonical name before the lookup.
#
# Remove when: upstream resolves `cr` and `yml` by name.

require "tartrazine"

module Tartrazine
  HWARO_LEXER_ALIASES = {"cr" => "crystal", "yml" => "yaml"}

  private def self.lexer_by_name(name : String) : BaseLexer
    previous_def(HWARO_LEXER_ALIASES.fetch(name.downcase, name))
  end
end
