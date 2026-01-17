# Hwaro - A fast and lightweight static site generator
#
# This is the main entry point for the Hwaro application.
# The codebase is organized as follows:
#
# - options/   : Option structs for each command (BuildOptions, ServeOptions, etc.)
# - core/      : Core functionality modules (Build, Serve, Init)
# - cli/       : Command-line interface handling
#   - commands/: Individual command implementations
#   - runner.cr: Main CLI runner

require "option_parser"
require "yaml"
require "ecr"
require "file_utils"
require "http/server"
require "markd"
require "toml"

# Load options
require "./hwaro/options/init_options"
require "./hwaro/options/build_options"
require "./hwaro/options/serve_options"

# Load core modules
require "./hwaro/core/init"
require "./hwaro/core/build"
require "./hwaro/core/serve"

# Load CLI
require "./hwaro/cli/runner"

module Hwaro
  VERSION = "0.1.0"
end

Hwaro::CLI::Runner.new.run
