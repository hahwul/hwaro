# Legacy compatibility - delegates to Core::Build
# This file is kept for backward compatibility with code that may reference Hwaro::Build directly.

require "./core/build"

module Hwaro
  # Alias for backward compatibility
  alias Build = Core::Build
  alias SiteConfig = Core::SiteConfig
end
