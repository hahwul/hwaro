require "../../spec_helper"

describe Hwaro::Content::DiscoveryPages do
  describe ".reject_excluded!" do
    it "drops pages under an excluded prefix" do
      keep = Hwaro::Models::Page.new("b/x.md")
      keep.url = "/b/x/"
      drop = Hwaro::Models::Page.new("a/x.md")
      drop.url = "/a/x/"

      Hwaro::Content::DiscoveryPages.reject_excluded!([keep, drop], ["/a/"]).should eq([keep])
    end

    it "matches an NFC pattern against an NFD url (and the reverse)" do
      nfc = "\uAC00sec"
      nfd = "가sec"

      {nfc => nfd, nfd => nfc}.each do |pattern, url_name|
        drop = Hwaro::Models::Page.new("#{url_name}/a.md")
        drop.url = "/#{url_name}/a/"
        keep = Hwaro::Models::Page.new("other/a.md")
        keep.url = "/other/a/"

        Hwaro::Content::DiscoveryPages.reject_excluded!([drop, keep], ["/#{pattern}/"]).should eq([keep])
      end
    end
  end
end
