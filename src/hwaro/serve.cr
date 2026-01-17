# Legacy compatibility - delegates to Core::Serve
# This file is kept for backward compatibility with code that may reference Hwaro::Serve directly.

require "./core/serve"

module Hwaro
  # Alias for backward compatibility
  alias Serve = Core::Serve
  alias IndexRewriteHandler = Core::IndexRewriteHandler
end
