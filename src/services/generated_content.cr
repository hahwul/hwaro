# Plans `[[content.generate]]` rows for the content-walking tool commands
# (`tool list`, `tool stats`), so both agree with each other AND with what
# a build actually publishes (publish-state parity: ContentLister is the
# SoT for authored files; this is its counterpart for generated pages).
#
# Planning is deliberately network-free: it reads the working directory's
# config.toml plus local `data/` files. Rules over a not-yet-fetched
# [[data.remote]] key get a note instead of rows, a key that BOTH disk and
# remote provide is called out as the hard config error every build hits,
# and one bad rule degrades to a warning without discarding the rows of
# healthy rules.

require "crinja"
require "./content_lister"
require "../models/config"
require "../core/build/data_disk"
require "../core/build/content_generate"
require "../content/processors/template"
require "../utils/date_utils"
require "../utils/errors"
require "../utils/logger"

module Hwaro
  module Services
    module GeneratedContent
      extend self

      # ContentInfo rows for every `[[content.generate]]` page this
      # project's local data can plan. Empty when the listing does not
      # target THIS project's content dir: config.toml and `data/` are
      # resolved from the working directory, so planning against a foreign
      # `--content-dir` would interleave this project's generated rows into
      # another site's listing.
      def infos(content_dir : String) : Array(ContentInfo)
        unless File.expand_path(content_dir) == File.expand_path("content")
          Logger.debug "Generated-content rows are only planned for this project's content/ (got --content-dir #{content_dir})."
          return [] of ContentInfo
        end
        return [] of ContentInfo unless File.exists?("config.toml")

        config = begin
          Models::Config.load
        rescue Exception
          # An unloadable config disables generated rows, not the listing.
          return [] of ContentInfo
        end
        return [] of ContentInfo if config.content_generate.empty?

        disk_data = Core::Build::DataDisk.load_hash
        remote_keys = config.data_remote.map(&.key.downcase)
        env = Content::Processors::TemplateEngine.new.env
        now = Time.utc

        infos = [] of ContentInfo
        config.content_generate.each do |rule|
          root_key = rule.source.split('.').first
          if remote_keys.includes?(root_key.downcase)
            if disk_data.has_key?(root_key)
              # Mirror Initialize#load_remote_data: two sources for one key
              # is a hard config error, so no build can publish these rows.
              Logger.warn "  [[content.generate]] \"#{rule.source}\": site.data.#{root_key} has both a data/ file and a [[data.remote]] source — every build fails on this config, so its rows are not listed."
            else
              Logger.info "  [[content.generate]] \"#{rule.source}\": remote source — its pages appear after a build fetches site.data.#{root_key}."
            end
            next
          end

          # Rule-by-rule so one bad rule cannot take down the rows of the
          # healthy ones (matching the build, which names the bad rule).
          plans = begin
            Core::Build::ContentGenerate.plan([rule], disk_data, env, include_bodies: false)
          rescue ex : Hwaro::HwaroError
            Logger.warn "  Skipping [[content.generate]] \"#{rule.source}\" rows: #{ex.message}"
            next
          end

          plans.each do |plan|
            # Authored-wins, exactly like the build: a contested path lists
            # the authored file only, never a duplicate generated row.
            next if Core::Build::ContentGenerate.authored_twin_exists?(plan.path)

            date = plan.date_raw.try { |raw| Utils::DateUtils.parse_content_date(raw) }
            state = date && date > now ? PublishState::Future : PublishState::Published
            infos << ContentInfo.new(
              path: plan.path,
              title: plan.title,
              draft: false,
              date: date,
              state: state,
              generated_from: plan.origin,
            )
          end
        end
        infos
      end
    end
  end
end
