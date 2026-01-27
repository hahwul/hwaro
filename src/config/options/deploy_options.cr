module Hwaro
  module Config
    module Options
      struct DeployOptions
        property source_dir : String?
        property targets : Array(String)
        property dry_run : Bool?
        property confirm : Bool?
        property force : Bool?
        property max_deletes : Int32?

        def initialize(
          @source_dir : String? = nil,
          @targets : Array(String) = [] of String,
          @dry_run : Bool? = nil,
          @confirm : Bool? = nil,
          @force : Bool? = nil,
          @max_deletes : Int32? = nil,
        )
        end
      end
    end
  end
end

