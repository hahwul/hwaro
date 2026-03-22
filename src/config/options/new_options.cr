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

        def initialize(
          @path : String? = nil,
          @title : String? = nil,
          @archetype : String? = nil,
          @date : String? = nil,
          @draft : Bool? = nil,
          @tags : Array(String) = [] of String,
          @section : String? = nil,
        )
        end
      end
    end
  end
end
