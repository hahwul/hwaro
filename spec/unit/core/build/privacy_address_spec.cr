require "../../../spec_helper"

private def internal?(address : String) : Bool
  Hwaro::Core::Build::Privacy.internal_address?(Socket::IPAddress.new(address, 0))
end

describe "Privacy.internal_address?" do
  it "flags loopback, private, link-local, CGNAT, unspecified, multicast and mapped forms" do
    %w[
      127.0.0.1 10.1.2.3 172.16.0.1 172.31.255.255 192.168.1.1 169.254.169.254
      100.64.0.1 100.127.255.255 0.0.0.0 224.0.0.1 255.255.255.255
      ::1 :: fc00::1 fd12::1 fe80::1 ff02::1
      ::ffff:127.0.0.1 ::ffff:10.0.0.1 ::ffff:169.254.169.254 ::ffff:100.64.0.1
      64:ff9b::7f00:1 64:ff9b::a9fe:a9fe 64:ff9b::10.0.0.1 192.0.0.192 192.0.0.1 fec0::1 feff::1
    ].each { |a| internal?(a).should(be_true, a) }
  end

  it "lets public addresses through" do
    %w[8.8.8.8 1.1.1.1 100.63.255.255 100.128.0.1 172.32.0.1 192.0.1.1 2606:4700::1111 ::ffff:8.8.8.8 64:ff9b::808:808 ff::1].each do |a|
      internal?(a).should(be_false, a)
    end
  end
end

# `vet_hop` is what pins a privacy fetch: it must hand back the addresses
# it checked, not nil (which would connect by name and reopen rebinding).
class Hwaro::Core::Build::Privacy
  def test_vet_hop(url : String) : Array(String)?
    vet_hop(URI.parse(url))
  end
end

describe "Privacy#vet_hop" do
  config = load_config(%([privacy]\nenabled = true\ninclude = ["cdn.example"]))

  it "returns the vetted addresses for a public host, nil for an include-listed one" do
    privacy = Hwaro::Core::Build::Privacy.new(config, "public", cache_dir: File.join(Dir.tempdir, "hwaro-vet-hop-spec-none"))
    privacy.test_vet_hop("http://93.184.216.34/x").should eq(["93.184.216.34"])
    privacy.test_vet_hop("https://cdn.example/x").should be_nil
    expect_raises(Hwaro::Core::Build::Privacy::Refused) { privacy.test_vet_hop("http://127.0.0.1:1/x") }
  end
end
