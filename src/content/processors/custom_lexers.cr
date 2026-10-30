# User syntax-highlighting grammars from `[highlight] lexers_dir`.
#
# Every `*.xml` file directly in that directory is a Chroma/Pygments lexer
# (the format Tartrazine's bundled lexers use) and registers under its
# `<name>` and each `<alias>` (case-insensitive), so a ```mydsl fence
# highlights at build time. A custom name or alias wins over a bundled
# one (see ext/tartrazine_custom_lexers.cr).
#
# Failures never stop the build: a missing directory or a grammar that does
# not parse is a warning naming the file, and fences in that language fall
# back to plain output — the same as any language without a lexer.
# `hwaro doctor` reports the same problems (`highlight-lexer-invalid`).

require "digest/md5"
require "tartrazine"
require "../../ext/tartrazine_custom_lexers"

module Hwaro
  module Content
    module Processors
      module CustomLexers
        extend self

        # One parsed grammar file.
        record Grammar, path : String, names : Array(String), filenames : Array(String), template : Tartrazine::LexerTemplate

        # Content digest of the grammars the current build registered; ""
        # when none. Folded into the build-cache config hash and the body
        # memo fingerprint, so a grammar edit re-highlights every page.
        class_getter digest : String = ""

        # The grammar files in `dir`, sorted for a deterministic load order.
        def files(dir : String) : Array(String)
          Dir.glob(File.join(Utils::PathUtils.glob_escape(dir), "*.xml")).select { |path| File.file?(path) }.sort!
        end

        # Parse every grammar in `dir`. Returns the grammars to register, a
        # `{path, message}` problem for each file that did not load (or lost
        # a name to an earlier file), and a digest of the loaded files'
        # bytes ("" when none loaded). Each file is read once, and a read
        # failure is a problem like a parse failure — build and doctor both
        # report exactly this list.
        def scan(dir : String) : {Array(Grammar), Array({String, String}), String}
          grammars = [] of Grammar
          problems = [] of {String, String}
          md5 = Digest::MD5.new
          paths = begin
            files(dir)
          rescue ex
            problems << {dir, "not loaded — #{ex.message || ex.class.name}"}
            [] of String
          end
          paths.each do |path|
            xml = File.read(path)
            names, filenames, template = Tartrazine.hwaro_parse_custom_lexer(xml)
            grammars << Grammar.new(path, names, filenames, template)
            md5.update(path)
            md5.update("\0")
            md5.update(xml)
            md5.update("\0")
          rescue ex
            problems << {path, "not loaded — #{ex.message || ex.class.name}"}
          end
          grammars = drop_duplicate_names(grammars, problems)
          {grammars, problems, grammars.empty? ? "" : md5.final.hexstring}
        end

        # Register this build's grammars (replacing the previous build's —
        # serve rebuilds in one process) and return their digest. Called
        # once per build from the Initialize phase, before rendering.
        def apply(config : Models::Config) : String
          grammars = [] of Grammar
          new_digest = ""
          highlight = config.highlight
          if dir = highlight.lexers_dir
            if !highlight.enabled
              # Nothing is highlighted at all; nothing to say.
            elsif !highlight.server?
              Logger.warn "[highlight] lexers_dir is ignored with mode = \"client\": Highlight.js does not read Chroma grammars."
            elsif !Dir.exists?(dir)
              Logger.warn "[highlight] lexers_dir: #{dir} — directory not found; no custom grammars loaded."
            else
              grammars, problems, new_digest = scan(dir)
              problems.each { |path, message| Logger.warn "Syntax grammar #{path}: #{message}" }
            end
          end

          Tartrazine.hwaro_register_custom_lexers(grammars.map { |grammar| {grammar.names, grammar.filenames, grammar.template} })
          # Highlighted output memoized under the previous grammar set (or a
          # language remembered as having no lexer) is stale now.
          ServerHighlighter.reset_memos if new_digest != @@digest
          @@digest = new_digest
        end

        def custom?(lang : String) : Bool
          Tartrazine.hwaro_custom_lexer?(lang)
        end

        # The first file (in sorted order) to claim a name keeps it; a later
        # claim is a problem, and a file left with no names is not loaded.
        # A dropped file's bytes stay in the digest: harmless, it only
        # means editing it also invalidates the cache.
        private def drop_duplicate_names(grammars : Array(Grammar), problems : Array({String, String})) : Array(Grammar)
          owners = {} of String => String
          grammars.compact_map do |grammar|
            names = grammar.names.select do |name|
              if owner = owners[name]?
                problems << {grammar.path, "'#{name}' is already defined by #{owner}; keeping #{owner}"}
                false
              else
                owners[name] = grammar.path
                true
              end
            end
            names.empty? ? nil : grammar.copy_with(names: names)
          end
        end
      end
    end
  end
end
