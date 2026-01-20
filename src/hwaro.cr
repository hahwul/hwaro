# Hwaro - A fast and lightweight static site generator
#
# This is the main entry point for the Hwaro application.
# The codebase is organized as follows:
#
# - config/    : Configuration loading and options
#   - options/ : Command option structs (BuildOptions, ServeOptions, etc.)
# - core/      : Build orchestration (builder, cache, parallel, lifecycle)
# - content/   : Content domain
#   - processors/ : Content processors (markdown, html, etc.)
#   - seo/     : SEO file generators (sitemap, feeds, robots, llms)
#   - hooks/   : Lifecycle hook implementations
# - services/  : Non-build features (init, new, serve)
# - models/    : Data structures (config, page, site, etc.)
# - cli/       : Command-line interface
# - utils/     : Utility modules (logger, etc.)

require "option_parser"
require "yaml"
require "ecr"
require "file_utils"
require "http/server"
require "markd"
require "toml"

# Load utilities
require "./utils/logger"

# Load options
require "./config/options/init_options"
require "./config/options/build_options"
require "./config/options/serve_options"

# Load models
require "./models/config"
require "./models/page"
require "./models/section"
require "./models/site"
require "./models/toc"

# Load content processors
require "./content/processors/base"
require "./content/processors/markdown"
require "./content/processors/html"
require "./content/processors/syntax_highlighter"

# Load lifecycle system
require "./core/lifecycle"

# Load core modules
require "./core/build/cache"
require "./core/build/parallel"
require "./core/build/builder"

# Load services
require "./services/scaffolds/registry"
require "./services/initializer"
require "./services/creator"
require "./services/server/server"
require "./services/frontmatter_converter"
require "./services/content_lister"

# Load content domain
require "./content/seo/feeds"
require "./content/seo/sitemap"
require "./content/seo/robots"
require "./content/seo/llms"
require "./content/search"
require "./content/taxonomies"

# Load pagination
require "./content/pagination/paginator"
require "./content/pagination/renderer"

# Load content hooks
require "./content/hooks"

# Load CLI
require "./cli/runner"

module Hwaro
  VERSION = "0.1.0"
end
