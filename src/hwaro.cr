# Hwaro - A fast and lightweight static site generator
#
# This is the main entry point for the Hwaro application.
# The codebase is organized as follows:
#
# - options/   : Option structs for each command (BuildOptions, ServeOptions, etc.)
# - core/      : Core functionality modules
#   - build/   : Build-related modules (builder, cache, parallel)
#   - init/    : Project initialization
#   - serve/   : Development server
# - plugins/   : Extensible plugin system
#   - processors/ : Content processors (markdown, html, etc.)
# - cli/       : Command-line interface handling
#   - commands/: Individual command implementations
#   - runner.cr: Main CLI runner with command registry
# - utils/     : Utility modules (logger, etc.)
# - schemas/   : Data structures for config, pages, etc.

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
require "./options/init_options"
require "./options/build_options"
require "./options/serve_options"

# Load schemas
require "./schemas/config"
require "./schemas/page"
require "./schemas/section"
require "./schemas/site"
require "./schemas/toc"

# Load plugins
require "./plugins/processors/base"
require "./plugins/processors/markdown"
require "./plugins/processors/html"

# Load core modules
require "./core/build/cache"
require "./core/build/parallel"
require "./core/build/builder"
require "./core/init/initializer"
require "./core/serve/server"
require "./core/build/seo/feeds"
require "./core/build/seo/sitemap"

# Load CLI
require "./cli/runner"

module Hwaro
  VERSION = "0.1.0"
end

Hwaro::CLI::Runner.new.run
