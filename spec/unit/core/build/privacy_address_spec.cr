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
    ].each { |a| internal?(a).should(be_true, a) }
  end

  it "lets public addresses through" do
    %w[8.8.8.8 1.1.1.1 100.63.255.255 100.128.0.1 172.32.0.1 2606:4700::1111 ::ffff:8.8.8.8].each do |a|
      internal?(a).should(be_false, a)
    end
  end
end
