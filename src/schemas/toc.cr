module Hwaro
  module Schemas
    class TocHeader
      property level : Int32
      property id : String
      property title : String
      property permalink : String
      property children : Array(TocHeader)

      def initialize(@level : Int32, @id : String, @title : String, @permalink : String)
        @children = [] of TocHeader
      end
    end
  end
end
