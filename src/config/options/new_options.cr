module Hwaro
  module Config
    module Options
      class NewOptions
        property path : String?
        property title : String?
        property archetype : String?
        property date : String?
        property draft : Bool?
        property tags : Array(String)
        property section : String?
        # `--bundle` / `--no-bundle`. `nil` means "user didn't specify";
        # Creator then consults the archetype directive and the config
        # default in that order (CLI > archetype > config > single).
        property bundle : Bool?

        def initialize(
          @path : String? = nil,
          @title : String? = nil,
          @archetype : String? = nil,
          @date : String? = nil,
          @draft : Bool? = nil,
          @tags : Array(String) = [] of String,
          @section : String? = nil,
          @bundle : Bool? = nil,
        )
        end
      end
    end
  end
end
