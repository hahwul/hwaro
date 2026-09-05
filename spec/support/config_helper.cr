# Config-loading helpers shared by the config specs.
#
# `Models::Config.load` reads a file, so every config example used to carry
# its own tempfile dance — ten copies across spec/unit, each with a different
# tempfile prefix and the same body.

# Parse `toml` through the real loader (including env substitution, the
# unknown-key warning and every section loader) and return the Config.
def load_config(toml : String) : Hwaro::Models::Config
  File.tempfile("hwaro-config", ".toml") do |file|
    file.print(toml)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

# Assert that `toml` is rejected at load time with a classified config
# error, returning it for message assertions.
def expect_config_error(toml : String) : Hwaro::HwaroError
  err = expect_raises(Hwaro::HwaroError) { load_config(toml) }
  err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
  err
end
