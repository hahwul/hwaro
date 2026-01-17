# Legacy compatibility - delegates to Core::Init
# This file is kept for backward compatibility with code that may reference Hwaro::Init directly.

require "./core/init"

module Hwaro
  # Alias for backward compatibility
  alias Init = Core::Init
end
