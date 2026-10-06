# Patch for the stdlib YAML timestamp parser — kept here with the other
# vendored-library fixes.
#
# `Time::Format::YAML_DATE.parse?` resolves a timestamp with no zone
# (`date: 2024-03-05`, `date: 2024-03-05 10:00:00`) in UTC, while TOML
# local dates and every quoted/JSON date string are read in the machine's
# local zone. So the same front matter meant a different instant per format:
# in a +09:00 zone a YAML post dated today was in the future and hidden while
# its TOML twin published, JSON-LD offsets differed, and `tool convert`
# shifted the instant. Zone-less YAML timestamps now use the local zone, the
# TOML rule; `Z` and written offsets are kept exactly as before.

require "yaml"

module Time::Format::YAML_DATE # ameba:disable Naming/TypeNames -- stdlib name
  def self.parse?(string) : Time?
    parser = Parser.new(string)
    if parser.yaml_date_time?
      parser.time(Time::Location.local) rescue nil
    end
  end
end
