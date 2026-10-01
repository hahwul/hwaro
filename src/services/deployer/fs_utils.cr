# Deployer — filesystem helpers (content comparison, tree walking, path relations).
#
# Reopens `Services::Deployer`; deployer.cr keeps the result records, the
# three entry points (plan / run / deploy_structured) and per-target
# dispatch. Parts only reopen the class: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Deployer
      # Compare two files for identical content. Uses size check first,
      # then reads in 8 KiB chunks to avoid loading large files entirely
      # into memory for the common case where files differ early.
      private def same_file?(a : String, b : String) : Bool
        return false unless File.exists?(a) && File.exists?(b)
        return false unless File.info(a).size == File.info(b).size

        File.open(a, "rb") do |fa|
          File.open(b, "rb") do |fb|
            buf_a = Bytes.new(8192)
            buf_b = Bytes.new(8192)
            loop do
              # IO#read may return fewer bytes than requested without being at
              # EOF; fill each buffer fully so a short read on one side isn't
              # mistaken for a content difference.
              read_a = read_fully(fa, buf_a)
              read_b = read_fully(fb, buf_b)
              return false unless read_a == read_b
              return true if read_a == 0
              return false unless buf_a[0, read_a] == buf_b[0, read_b]
            end
          end
        end
      rescue ex : IO::Error | File::Error
        Logger.debug "File comparison failed for #{a} vs #{b}: #{ex.message}"
        false
      rescue ex
        Logger.debug "File comparison failed: #{ex.message}"
        false
      end

      # Read until `slice` is full or EOF; returns the byte count (< slice
      # size only at EOF).
      private def read_fully(io : IO, slice : Bytes) : Int32
        total = 0
        while total < slice.size
          read = io.read(slice[total, slice.size - total])
          break if read == 0
          total += read
        end
        total
      end

      # Prune the directories the delete pass emptied: the parents of each
      # deleted entry, deepest first, up to (never including) `root`. Only
      # those — sweeping every empty directory under the destination removed
      # ones the sync never selected (an empty `uploads/` outside `include`,
      # a placeholder the server expects), without a line in the plan.
      # lstat throughout, so a symlinked parent is never followed or removed.
      private def prune_emptied_directories(root : String, deleted : Array(String)) : Nil
        candidates = Set(String).new
        deleted.each do |rel|
          parent = File.dirname(rel)
          until parent == "." || parent.empty? || parent == "/"
            break unless candidates.add?(parent)
            parent = File.dirname(parent)
          end
        end

        candidates.to_a.sort_by! { |rel| -rel.count('/') }.each do |rel|
          full = File.join(root, rel)
          begin
            info = File.info?(full, follow_symlinks: false)
            next unless info && info.directory?
            Dir.delete(full) if Dir.empty?(full)
          rescue File::Error | IO::Error
            next
          end
        end
      end

      # Version-control metadata directories. A source tree that is itself a
      # checkout (`public/` as a gh-pages clone or submodule) must not ship
      # its repository; every other dot-directory the build wrote is content.
      private VCS_DIRS = {".git", ".svn", ".hg", ".bzr"}

      # Walk the regular files under `root`. `dot_dirs` decides which hidden
      # directories are entered: the source side (true) deploys every one but
      # VCS metadata, because the build publishes `static/` dot-paths and the
      # deploy docs promise to ship them; the destination side (false) enters
      # only `.well-known`, so the delete pass never reaches into hidden state
      # it did not create there.
      private def each_project_file(root : String, follow_symlinks : Bool = true, dot_dirs : Bool = true, &block : String ->)
        visited = Set(String).new
        root_real = Hwaro::Utils::PathUtils.resolved_real_path(root)
        project_root_real = Hwaro::Utils::PathUtils.resolved_real_path(Dir.current)
        visited << root_real
        walk_project_files(root, root_real, project_root_real, visited, follow_symlinks, dot_dirs, &block)
      end

      private def walk_project_files(
        dir : String,
        source_root_real : String,
        project_root_real : String,
        visited : Set(String),
        follow_symlinks : Bool,
        dot_dirs : Bool,
        &block : String ->
      )
        Dir.each_child(dir) do |entry|
          next if entry == ".DS_Store"
          full = File.join(dir, entry)
          # `public/` itself may be a symlink to an external output directory.
          # Follow links that stay within that resolved source root as well as
          # links within the project; reject links that escape both boundaries.
          if follow_symlinks && link_escapes_roots?(full, source_root_real, project_root_real)
            Logger.warn "Skipped symlink outside project and deploy source roots: #{full}"
            next
          end
          # info? follows symlinks; broken links and ELOOP entries are
          # skipped instead of crashing the deploy mid-walk.
          info = begin
            File.info?(full, follow_symlinks: follow_symlinks)
          rescue File::Error | IO::Error
            nil
          end
          next unless info
          if !follow_symlinks && info.symlink?
            # Report the link itself so the delete pass can unlink a stale
            # one, without ever reading through it.
            block.call(full)
            next
          end
          if info.directory?
            if entry.starts_with?(".")
              next if VCS_DIRS.includes?(entry)
              next unless dot_dirs || entry == ".well-known"
            end
            # Track resolved paths so symlink cycles (public/a → public) and
            # multiple links to the same directory are walked at most once.
            real = begin
              File.realpath(full)
            rescue File::Error | IO::Error
              next
            end
            next if visited.includes?(real)
            visited << real
            walk_project_files(full, source_root_real, project_root_real, visited, follow_symlinks, dot_dirs, &block)
          elsif info.file?
            block.call(full)
          end
        end
      end

      # True only for a symlink that resolves, and resolves outside both
      # roots. Dangling and looping links do not resolve at all; they fall
      # through to the `File.info?` check below and are skipped silently, as
      # they always were, instead of being reported as escaping the project.
      private def link_escapes_roots?(path : String, source_root_real : String, project_root_real : String) : Bool
        return false unless File.symlink?(path)
        real = begin
          File.realpath(path)
        rescue File::Error | IO::Error
          return false
        end
        !within_real_root?(real, project_root_real) && !within_real_root?(real, source_root_real)
      end

      private def within_real_root?(real : String, root_real : String) : Bool
        real == root_real || real.starts_with?(root_real + File::SEPARATOR)
      end

      private def relative_to(path : String, root : String) : String
        normalized_root = root.gsub('\\', '/')
        normalized_root += "/" unless normalized_root.ends_with?("/")
        normalized_path = path.gsub('\\', '/')
        rel =
          if normalized_path.starts_with?(normalized_root)
            normalized_path[normalized_root.size, normalized_path.size - normalized_root.size]
          else
            normalized_path
          end
        rel.starts_with?("/") ? rel.lchop('/') : rel
      end

      # True when `b` is `a` or lies under it. Both are absolute, resolved
      # paths.
      private def nested_path?(a : String, b : String) : Bool
        return false if a.empty? || b.empty?
        a = a.rstrip('/')
        b = b.rstrip('/')
        # Identical directories also count as overlap — otherwise a
        # source == destination config slips past the overlap refusal and a
        # strip_index_html target can mutate/delete the source tree.
        return true if a == b
        # `/` strips to "" and contains everything; it used to fall out as
        # "no overlap", so `path = "/"` walked (and would sync over) the
        # whole filesystem.
        return true if a.empty?
        return false if b.empty?
        b.starts_with?(a + "/")
      end
    end
  end
end
