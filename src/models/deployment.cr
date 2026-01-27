require "toml"

module Hwaro
  module Models
    class DeploymentMatcher
      property pattern : String
      property cache_control : String?
      property content_type : String?
      property gzip : Bool
      property force : Bool

      def initialize
        @pattern = ""
        @cache_control = nil
        @content_type = nil
        @gzip = false
        @force = false
      end
    end

    class DeploymentTarget
      property name : String
      property url : String
      property include : String?
      property exclude : String?
      property strip_index_html : Bool
      property command : String?

      def initialize
        @name = ""
        @url = ""
        @include = nil
        @exclude = nil
        @strip_index_html = false
        @command = nil
      end
    end

    class DeploymentConfig
      property target : String?
      property confirm : Bool
      property dry_run : Bool
      property force : Bool
      property max_deletes : Int32
      property workers : Int32
      property source_dir : String
      property targets : Array(DeploymentTarget)
      property matchers : Array(DeploymentMatcher)

      def initialize
        @target = nil
        @confirm = false
        @dry_run = false
        @force = false
        @max_deletes = 256
        @workers = 10
        @source_dir = "public"
        @targets = [] of DeploymentTarget
        @matchers = [] of DeploymentMatcher
      end

      def target_named(name : String) : DeploymentTarget?
        @targets.find { |t| t.name == name }
      end
    end
  end
end

