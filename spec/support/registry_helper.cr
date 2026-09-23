# Snapshot/restore for the process-global registries that
# spec/unit/registration_order_spec.cr pins.
#
# `crystal spec` runs every file in ONE process, and the order the files load
# in follows the filesystem glob, which differs between checkouts. A spec
# that registers a test processor or a synthetic CLI command and leaves it
# behind therefore breaks registration_order_spec only when it happens to
# load first — a failure that passes on rerun. Wrap such specs instead:
#
#   describe "..." do
#     around_each { |example| with_isolated_registries { example.run } }
#   end
#
# Everything is restored in `ensure`, so a failing example cannot leak
# either. Entries are restored in their original insertion order, which is
# what the registries' own iteration order (and the pinned lists) follow.

class Hwaro::CLI::CommandRegistry
  def self.__spec_snapshot
    {@@commands.dup, @@metadata.dup}
  end

  def self.__spec_restore(snapshot) : Nil
    @@commands = snapshot[0].dup
    @@metadata = snapshot[1].dup
  end
end

class Hwaro::CLI::Commands::ToolCommand
  def self.__spec_snapshot
    {@@sub_handlers.dup, @@sub_metadata.dup}
  end

  def self.__spec_restore(snapshot) : Nil
    @@sub_handlers = snapshot[0].dup
    @@sub_metadata = snapshot[1].dup
  end
end

class Hwaro::Services::Scaffolds::Registry
  def self.__spec_snapshot
    @@scaffolds.dup
  end

  def self.__spec_restore(snapshot) : Nil
    @@scaffolds = snapshot.dup
  end
end

# NOTE: snapshots hold references to the registered instances, not clones —
# an example must not mutate a registered processor's internal state.
def with_isolated_registries(&)
  processors = Hwaro::Content::Processors::Registry.names.compact_map do |name|
    Hwaro::Content::Processors::Registry.get(name)
  end
  commands = Hwaro::CLI::CommandRegistry.__spec_snapshot
  tool_subcommands = Hwaro::CLI::Commands::ToolCommand.__spec_snapshot
  scaffolds = Hwaro::Services::Scaffolds::Registry.__spec_snapshot
  begin
    yield
  ensure
    Hwaro::Content::Processors::Registry.clear
    processors.each { |p| Hwaro::Content::Processors::Registry.register(p) }
    Hwaro::CLI::CommandRegistry.__spec_restore(commands)
    Hwaro::CLI::Commands::ToolCommand.__spec_restore(tool_subcommands)
    Hwaro::Services::Scaffolds::Registry.__spec_restore(scaffolds)
  end
end
