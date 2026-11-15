require "../../../spec_helper"

describe Hwaro::Models::TemplatesConfig do
  it "escapes by default (1.0)" do
    Hwaro::Models::TemplatesConfig.new.autoescape.should be_true
    load_config(%(title = "x"\n)).templates.autoescape.should be_true
  end

  it "reads an explicit setting either way" do
    load_config(%(title = "x"\n[templates]\nautoescape = false\n)).templates.autoescape.should be_false
    load_config(%(title = "x"\n[templates]\nautoescape = true\n)).templates.autoescape.should be_true
  end
end
