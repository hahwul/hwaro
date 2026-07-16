# Monkey-patches for Tartrazine's tokenizer — kept here so we don't fork
# the vendored library, mirroring ext/crinja_resolve_fix.cr.
#
# Upstream Tartrazine is not safe to run from multiple -Dpreview_mt
# workers at once, which forced ServerHighlighter to funnel EVERY
# tokenization through one global mutex (see syntax_highlighter.cr
# history). Patches 1-4 below remove each piece of cross-thread shared
# mutable state so highlighting can run genuinely in parallel; patches
# 5-6 are allocation cuts on the tokenize hot path that are safe to drop
# independently of the thread-safety patches.
#
# Behavior is unchanged single-threaded: same match results (the
# per-thread buffer is sized from the same per-pattern capacity as the
# buffer it replaces), same tokens, same fallbacks. The no-match empty
# arrays are shared frozen constants — callers never mutate them
# (UnconditionalRule::NO_MATCH set that precedent upstream).
#
# No upstream issue is filed yet for any of these (as of 2026-07).
# Removal criteria are listed per patch; a tartrazine version bump must
# re-check each section against the shard's source.

require "tartrazine"

# === 1. Thread-safe PCRE2 matching ======================================
# Upstream BytesRegex::Regex allocates ONE match_data buffer per compiled
# pattern and reuses it for every match() call. Compiled rules are shared
# between all lexer instances via the template cache, so two workers
# matching the same rule corrupted each other's ovectors. Matching now
# writes into a per-thread scratch buffer — PCRE2 compiled patterns
# themselves are read-only and explicitly documented as safe to share
# across threads.
# Remove when: upstream stops sharing match_data across concurrent
# match() calls (per-call, per-thread, or lock-guarded).
module BytesRegex
  class Regex
    # Shared empty result for the no-match path (allocation cut — misses
    # vastly outnumber hits). Callers only ever read it (`match.size == 0`
    # / indexing after a hit), so one instance serves every miss.
    EMPTY_MATCHES = [] of Match

    # Capacity the pattern needs (capture_count + 1), memoized from the
    # stock per-pattern @match_data on first use so the hot path skips
    # the FFI call. 0 is never a valid ovector count (minimum is 1), so
    # it doubles as the unset sentinel. Concurrent first-time writers all
    # store the same value — an idempotent, aligned 32-bit store.
    @ovector_pairs : UInt32 = 0_u32

    # One scratch match_data per OS thread, grown to the widest pattern
    # that thread has matched so far. A fiber cannot be preempted between
    # acquiring the buffer and reading its ovector (there is no yield
    # point inside #match), and fibers never migrate threads mid-call,
    # so the buffer is exclusive for the duration of each match. The
    # buffer is freed only when it grows; a thread that exits keeps its
    # last buffer alive — a bounded one-per-thread leak that is moot
    # while preview_mt workers live for the whole process.
    @[ThreadLocal]
    @@scratch_md = Pointer(LibPCRE2::MatchData).null
    @[ThreadLocal]
    @@scratch_pairs = 0_u32

    protected def self.scratch_match_data(pairs : UInt32) : LibPCRE2::MatchData*
      if @@scratch_md.null? || @@scratch_pairs < pairs
        LibPCRE2.match_data_free(@@scratch_md) unless @@scratch_md.null?
        @@scratch_md = LibPCRE2.match_data_create(pairs, nil)
        @@scratch_pairs = pairs
      end
      @@scratch_md
    end

    def match(str : Bytes, pos = 0) : Array(Match)
      # The stock @match_data still exists (created from the pattern at
      # compile time and freed by the stock finalize); it is no longer
      # written to — its capacity is read once to size the thread-local
      # buffer.
      pairs = @ovector_pairs
      if pairs == 0
        pairs = @ovector_pairs = LibPCRE2.get_ovector_count(@match_data)
      end
      match_data = Regex.scratch_match_data(pairs)

      rc = LibPCRE2.match(
        @re,
        str,
        str.size,
        pos,
        LibPCRE2::NO_UTF_CHECK,
        match_data,
        nil)
      if rc > 0
        ovector = LibPCRE2.get_ovector_pointer(match_data)
        (0...rc).map do |i|
          m_start = ovector[2 * i]
          m_end = ovector[2 * i + 1]
          if m_start == m_end
            m_value = Bytes.new(0)
          else
            m_value = str[m_start...m_end]
          end
          Match.new(m_value, m_start, m_end - m_start)
        end
      else
        EMPTY_MATCHES
      end
    end
  end
end

module Tartrazine
  # Shared empty result for rule misses (allocation cut, see patch 5).
  # Never mutated: the only consumer iterates it into a deque.
  EMPTY_TOKENS = [] of Token

  # === 2. Synchronized template cache ===================================
  # The stock fast path read @@lexer_templates without the mutex while
  # first-use writers mutated it inside the mutex (double-checked locking
  # on a non-atomic Hash). Template parsing happens once per language per
  # process; a plain full synchronize costs one lock per lexer
  # ACQUISITION (per code block), which is noise next to tokenization.
  # Remove when: upstream guards the cached-read path (mutex, RWLock, or
  # atomic snapshot).
  private def self.get_or_create_template(lexer_file_name : String) : LexerTemplate
    @@template_mutex.synchronize do
      if template = @@lexer_templates[lexer_file_name]?
        return template
      end

      xml = LexerFiles.get("/#{lexer_file_name}.xml").gets_to_end
      template = parse_xml_to_template(xml)
      @@lexer_templates[lexer_file_name] = template
      template
    end
  end

  # === 3. Per-instance states Hash ======================================
  # Stock handed every lexer instance the TEMPLATE's own states Hash. A
  # `combined` action then inserted its synthesized state into that
  # shared Hash mid-tokenization — a data race, and a leak (random-named
  # states accumulated in the template forever). Each instance now gets a
  # shallow copy; the State structs and their immutable rule arrays stay
  # shared.
  # Remove when: upstream isolates per-instance state mutation (own Hash
  # per lexer, or combined-state storage moved off the shared template).
  private def self.create_from_template(lexer_file_name : String) : BaseLexer
    template = get_or_create_template(lexer_file_name)

    lexer = RegexLexer.new
    lexer.config = {
      name:             template.config[:name].as(String),
      priority:         template.config[:priority].as(Float64),
      case_insensitive: template.config[:case_insensitive].as(Bool),
      dot_all:          template.config[:dot_all].as(Bool),
      not_multiline:    template.config[:not_multiline].as(Bool),
      ensure_nl:        template.config[:ensure_nl].as(Bool),
    }
    lexer.states = template.states.dup
    lexer
  end

  # === 4. Deterministic combined-state names ============================
  # Stock named combined states with Random.base58, and the base58
  # shard's global RNG is not documented thread-safe. The name only needs
  # to be unique within one lexer instance's (now private, see patch 3)
  # states Hash, so derive it deterministically from the operand names.
  # The NUL separator cannot appear in XML-sourced state names, so a
  # synthesized name can only collide with the SAME combination — which
  # maps to identical rules anyway.
  # Remove when: upstream names combined states without shared RNG state
  # (and patch 3 is no longer needed).
  struct State
    def +(other : State)
      new_state = State.new
      new_state.name = "#{name}\0+\0#{other.name}"
      new_state.rules = rules + other.rules
      new_state
    end
  end

  # === 5. Allocation cuts in rule matching (perf only) ==================
  # Stock allocated `[] of Token` (and `[] of Match` inside BytesRegex)
  # on every failed rule attempt — one GC allocation per rule per
  # position scanned — plus a flat_map re-copy of the emitted tokens for
  # the overwhelmingly common single-action rule. Safe to drop without
  # affecting thread-safety.
  struct Rule
    def match(text : Bytes, pos, tokenizer) : Tuple(Bool, Int32, Array(Token))
      match = pattern.match(text, pos)

      return false, pos, EMPTY_TOKENS if match.size == 0
      # `flat_map` over a 1-element actions array only re-copies the
      # Array(Token) that #emit just built (flattening one level of an
      # already-flat array) — return emit's array directly instead.
      # Callers only ever iterate the result.
      tokens = if @actions.size == 1
                 @actions.unsafe_fetch(0).emit(match, tokenizer)
               else
                 @actions.flat_map(&.emit(match, tokenizer))
               end
      return true, pos + match[0].size, tokens
    end
  end

  struct IncludeStateRule
    def match(text : Bytes, pos : Int32, tokenizer : Tokenizer) : Tuple(Bool, Int32, Array(Token))
      tokenizer.@lexer.states[@state].rules.each do |rule|
        matched, new_pos, new_tokens = rule.match(text, pos, tokenizer)
        return true, new_pos, new_tokens if matched
      end
      return false, pos, EMPTY_TOKENS
    end
  end

  # === 6. Identity fast path in split_tokens (perf only) ================
  # Stock rebuilt a fresh Array(Token) on every rule hit even though
  # token values only rarely contain a newline. When none does, the split
  # is the identity transform (each token maps to itself in order), so
  # return the input array untouched — the only caller iterates it into
  # the deque and never mutates it.
  class Tokenizer
    def split_tokens(tokens : Array(Token)) : Array(Token)
      return tokens unless tokens.any?(&.[:value].includes?('\n'))

      split_tokens = [] of Token
      tokens.each do |token|
        if token[:value].includes?("\n")
          values = token[:value].split("\n")
          values.each_with_index do |value, index|
            value += "\n" if index < values.size - 1
            split_tokens << {type: token[:type], value: value}
          end
        else
          split_tokens << token
        end
      end
      split_tokens
    end
  end
end
