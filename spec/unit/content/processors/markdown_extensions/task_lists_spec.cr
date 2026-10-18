require "../../../../spec_helper"

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe ".preprocess_task_lists" do
    it "accepts up to four spaces after the list marker, like GFM" do
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_task_lists("-   [x] wide\n1.  [ ] aligned\n-     [x] code")
      result.should contain(%(-   <input type="checkbox" checked disabled> wide))
      result.should contain(%(1.  <input type="checkbox" disabled> aligned))
      result.should contain("-     [x] code")
    end
  end
end
