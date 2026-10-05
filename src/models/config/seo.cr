# Config section — sitemap, robots, llms and feeds.
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    class SitemapConfig
      property enabled : Bool
      property filename : String
      property changefreq : String
      property priority : Float64
      property exclude : Array(String)

      def initialize
        @enabled = false
        @filename = "sitemap.xml"
        @changefreq = "weekly"
        @priority = 0.5
        @exclude = [] of String
      end
    end

    class RobotsRule
      # `content_signal` config keys and the Content-Signal names they emit,
      # in emission order (https://contentsignals.org/).
      CONTENT_SIGNAL_KEYS = {"search" => "search", "ai_input" => "ai-input", "ai_train" => "ai-train"}

      property user_agent : String
      property allow : Array(String)
      property disallow : Array(String)
      # Emitted (name, value) pairs in CONTENT_SIGNAL_KEYS order; empty
      # means no `Content-Signal:` line.
      property content_signal : Array({String, Bool})

      def initialize(user_agent : String)
        @user_agent = user_agent
        @allow = [] of String
        @disallow = [] of String
        @content_signal = [] of {String, Bool}
      end
    end

    class RobotsConfig
      property enabled : Bool
      property filename : String
      property rules : Array(RobotsRule)

      def initialize
        @enabled = true
        @filename = "robots.txt"
        @rules = [] of RobotsRule
      end
    end

    class LlmsConfig
      property enabled : Bool
      property filename : String
      property instructions : String
      property full_enabled : Bool
      property full_filename : String

      def initialize
        @enabled = true
        @filename = "llms.txt"
        @instructions = ""
        @full_enabled = false
        @full_filename = "llms-full.txt"
      end
    end

    class FeedConfig
      property enabled : Bool
      property filename : String
      property type : String
      property truncate : Int32
      property limit : Int32
      property sections : Array(String)
      property default_language_only : Bool
      property full_content : Bool

      def initialize
        @enabled = false
        @filename = ""
        @type = "rss"
        @truncate = 0
        @limit = 10
        @sections = [] of String
        @default_language_only = true
        @full_content = true
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_sitemap(config : Config)
        # Backward compatibility: `sitemap = true|false` predates the
        # `[sitemap]` table. `warn_mistyped_sections` exempts this form
        # (BOOLEAN_SECTION_KEYS), so both values must really be applied.
        sitemap_bool = config.raw["sitemap"]?.try(&.as_bool?)
        if !sitemap_bool.nil?
          config.sitemap.enabled = sitemap_bool
        elsif s = config.raw["sitemap"]?.try(&.as_h?)
          config.sitemap.enabled = bool_value(s["enabled"]?, config.sitemap.enabled)
          config.sitemap.filename = s["filename"]?.try(&.as_s?) || config.sitemap.filename
          validate_output_filename!("sitemap", "filename", config.sitemap.filename, "sitemap.xml", allow_empty: false)
          config.sitemap.changefreq = s["changefreq"]?.try(&.as_s?) || config.sitemap.changefreq
          # Keep the priority raw here (NOT clamped) so `hwaro doctor` can detect
          # an out-of-range value and warn/offer a fix. The sitemap EMITTER
          # (sitemap.cr) clamps to [0.0, 1.0] so the generated XML stays valid
          # even for users who never run doctor. NaN is the exception: it
          # sails through both doctor's range checks and the emitter's clamp
          # (NaN comparisons are all false) and lands in the XML as "NaN",
          # so non-finite values fall back to the default here.
          pr = float_value(s["priority"]?, config.sitemap.priority)
          config.sitemap.priority = pr.finite? ? pr : config.sitemap.priority
          if exclude = string_list?(s["exclude"]?, "[sitemap] exclude")
            config.sitemap.exclude = exclude
          end
        end
      end

      private def self.load_robots(config : Config)
        return unless s = config.raw["robots"]?.try(&.as_h?)

        config.robots.enabled = bool_value(s["enabled"]?, config.robots.enabled)
        config.robots.filename = s["filename"]?.try(&.as_s?) || config.robots.filename
        validate_output_filename!("robots", "filename", config.robots.filename, "robots.txt", allow_empty: false)

        if rules = s["rules"]?.try(&.as_a?)
          config.robots.rules = rules.compact_map do |rule_any|
            if rule_h = rule_any.as_h?
              user_agent = rule_h["user_agent"]?.try(&.as_s?) || "*"
              rule = RobotsRule.new(user_agent)
              rule.allow = string_or_array(rule_h["allow"]?)
              rule.disallow = string_or_array(rule_h["disallow"]?)
              if signal = rule_h["content_signal"]?
                rule.content_signal = robots_content_signal(signal, user_agent)
              end
              rule
            end
          end
        end
      end

      # `[[robots.rules]] content_signal = { search = true, ai_train = false }`
      # → ordered (name, value) pairs. Anything but a table of known bool
      # keys is a config error: a typo'd key silently dropping an
      # `ai-train=no` would publish the opposite of what the site asked for.
      private def self.robots_content_signal(raw : TOML::Any, user_agent : String) : Array({String, Bool})
        where = "[robots] rules (user_agent #{user_agent.inspect}) content_signal"
        table = raw.as_h? || raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Invalid #{where} = #{raw.raw.inspect}: expected a table.",
          hint: "Use content_signal = { search = true, ai_input = true, ai_train = false }.",
        )
        table.each do |key, value|
          unless RobotsRule::CONTENT_SIGNAL_KEYS.has_key?(key)
            suggestion = Utils::CommandSuggester.suggest(key, RobotsRule::CONTENT_SIGNAL_KEYS.keys).try { |k| "Did you mean '#{k}'? " } || ""
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONFIG,
              message: "Unknown #{where} key #{key.inspect}.",
              hint: "#{suggestion}Valid keys are search, ai_input and ai_train.",
            )
          end
          if value.as_bool?.nil?
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONFIG,
              message: "Invalid #{where} #{key} = #{value.raw.inspect}: expected true or false.",
              hint: "Set #{key} = true or #{key} = false, or remove it.",
            )
          end
        end
        RobotsRule::CONTENT_SIGNAL_KEYS.compact_map do |key, name|
          table[key]?.try(&.as_bool?).try { |v| {name, v} }
        end
      end

      private def self.load_llms(config : Config)
        return unless s = config.raw["llms"]?.try(&.as_h?)

        config.llms.enabled = bool_value(s["enabled"]?, config.llms.enabled)
        config.llms.filename = s["filename"]?.try(&.as_s?) || config.llms.filename
        config.llms.instructions = s["instructions"]?.try(&.as_s?) || config.llms.instructions
        config.llms.full_enabled = bool_value(s["full_enabled"]?, config.llms.full_enabled)
        config.llms.full_filename = s["full_filename"]?.try(&.as_s?) || config.llms.full_filename
        # Empty stays legal here: llms.cr already substitutes llms.txt /
        # llms-full.txt for an empty value, so those configs build today.
        validate_output_filename!("llms", "filename", config.llms.filename, "llms.txt", allow_empty: true)
        validate_output_filename!("llms", "full_filename", config.llms.full_filename, "llms-full.txt", allow_empty: true)
      end

      private def self.load_feeds(config : Config)
        return unless s = config.raw["feeds"]?.try(&.as_h?)

        # Backward compatibility for 'generate' property
        enabled = s["enabled"]?.try(&.as_bool?)
        generate = s["generate"]?.try(&.as_bool?)

        if !enabled.nil?
          config.feeds.enabled = enabled
        elsif !generate.nil?
          config.feeds.enabled = generate
        end

        config.feeds.filename = s["filename"]?.try(&.as_s?) || config.feeds.filename
        # Empty is the shipped default (safe_feed_filename derives rss.xml /
        # atom.xml / feed.json from `type`), so only non-file values are rejected.
        validate_output_filename!("feeds", "filename", config.feeds.filename, "rss.xml", allow_empty: true)
        if feed_type = s["type"]?.try(&.as_s?)
          # The writer only knows RSS, Atom and JSON Feed and published
          # anything else as RSS without a word.
          normalized = feed_type.strip.downcase
          if {"rss", "atom", "json"}.includes?(normalized)
            config.feeds.type = normalized
          else
            Logger.warn "Unknown [feeds] type '#{feed_type}' — expected \"rss\", \"atom\" or \"json\". Using \"#{config.feeds.type}\"."
          end
        end
        config.feeds.truncate = int_value(s["truncate"]?, config.feeds.truncate)
        config.feeds.limit = int_value(s["limit"]?, config.feeds.limit)
        if sections = string_list?(s["sections"]?, "[feeds] sections")
          config.feeds.sections = sections
        end
        config.feeds.default_language_only = bool_value(s["default_language_only"]?, config.feeds.default_language_only)
        config.feeds.full_content = bool_value(s["full_content"]?, config.feeds.full_content)
      end
    end
  end
end
