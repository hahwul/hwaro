require "../../../spec_helper"

describe "[csp] config" do
  it "defaults to off, headers mode" do
    csp = load_config(%(title = "T")).csp
    csp.enabled.should be_false
    csp.mode.should eq("headers")
    csp.headers_file.should eq("_headers")
    csp.report_only.should be_false
    csp.directives.should be_empty
  end

  it "parses every key, keeping directive order" do
    csp = load_config(<<-TOML).csp
      [csp]
      enabled = true
      mode = "meta"
      headers_file = "/cf/_headers"

      [csp.directives]
      img-src = "'self'   data: https://img.example.com"
      default-src = "'none'"
      frame-ancestors = ""
      TOML
    csp.enabled.should be_true
    csp.meta?.should be_true
    csp.headers_file.should eq("cf/_headers")
    csp.directives.to_a.should eq([
      {"img-src", "'self' data: https://img.example.com"},
      {"default-src", "'none'"},
      {"frame-ancestors", ""},
    ])
  end

  it "rejects report_only in meta mode" do
    expect_config_error(%([csp]\nenabled = true\nmode = "meta"\nreport_only = true)).message.to_s.should contain("report_only cannot be used with mode = \"meta\"")
  end

  it "allows report_only in meta mode while CSP is off" do
    load_config(%([csp]\nmode = "meta"\nreport_only = true)).csp.report_only.should be_true
  end

  it "rejects a bad mode, directive name or value" do
    expect_config_error(%([csp]\nmode = "http")).message.to_s.should contain("unknown mode")
    expect_config_error(%([csp.directives]\n"Img_Src" = "'self'")).message.to_s.should contain("is not a directive name")
    expect_config_error(%([csp.directives]\nimg-src = 1)).message.to_s.should contain("must be a string")
    expect_config_error(%([csp.directives]\nimg-src = "'self'; script-src *")).message.to_s.should contain("must not contain")
    expect_config_error(%([csp]\nheaders_file = "")).message.to_s.should contain("headers_file")
  end

  it "warns on unknown keys" do
    log = with_captured_log { load_config(%([csp]\nenabeld = true)) }
    log.should contain("[csp]: unknown key 'enabeld'")
  end
end
