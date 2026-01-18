# Build phases definition for Hwaro SSG
#
# Phases define the sequential stages of the build process.
# Each phase has before/after hook points for extensibility.

module Hwaro
  module Core
    module Lifecycle
      # Build phases executed in order
      enum Phase
        Initialize    # Setup cache, output directory, load config
        ReadContent   # Collect content files from filesystem
        ParseContent  # Parse front matter and extract metadata
        Transform     # Content transformation (e.g., Markdown → HTML)
        Render        # Apply templates to transformed content
        Generate      # Generate SEO files, search index, etc.
        Write         # Write rendered pages to filesystem
        Finalize      # Cleanup, save cache, final operations
      end

      # Hook points - before/after each phase
      enum HookPoint
        BeforeInitialize
        AfterInitialize
        BeforeReadContent
        AfterReadContent
        BeforeParseContent
        AfterParseContent
        BeforeTransform
        AfterTransform
        BeforeRender
        AfterRender
        BeforeGenerate
        AfterGenerate
        BeforeWrite
        AfterWrite
        BeforeFinalize
        AfterFinalize
      end

      # Maps Phase to its before/after HookPoints
      def self.hook_points_for(phase : Phase) : Tuple(HookPoint, HookPoint)
        case phase
        when Phase::Initialize
          {HookPoint::BeforeInitialize, HookPoint::AfterInitialize}
        when Phase::ReadContent
          {HookPoint::BeforeReadContent, HookPoint::AfterReadContent}
        when Phase::ParseContent
          {HookPoint::BeforeParseContent, HookPoint::AfterParseContent}
        when Phase::Transform
          {HookPoint::BeforeTransform, HookPoint::AfterTransform}
        when Phase::Render
          {HookPoint::BeforeRender, HookPoint::AfterRender}
        when Phase::Generate
          {HookPoint::BeforeGenerate, HookPoint::AfterGenerate}
        when Phase::Write
          {HookPoint::BeforeWrite, HookPoint::AfterWrite}
        when Phase::Finalize
          {HookPoint::BeforeFinalize, HookPoint::AfterFinalize}
        else
          raise "Unknown phase: #{phase}"
        end
      end
    end
  end
end
