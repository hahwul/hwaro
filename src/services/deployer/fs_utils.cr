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

      # Prune directories the delete pass emptied. Walks depth-first with
      # lstat instead of `Dir.glob`: glob expands `**` *through* symlinked
      # directories, so the old sweep could delete empty directories that
      # live outside the deploy root entirely. Dot-entries are left alone
      # (glob skipped them too, and the deploy never creates them).
      private def remove_empty_directories(root : String)
        prune_empty_directories(root)
      end

      private def prune_empty_directories(dir : String) : Nil
        # Children are collected before anything is deleted: unlinking during
        # an active `readdir` is unspecified by POSIX, and on filesystems that
        # compact the directory it can skip the siblings that follow.
        children = begin
          Dir.children(dir)
        rescue File::Error | IO::Error
          return
        end

        children.each do |entry|
          next if entry.starts_with?(".")
          full = File.join(dir, entry)
          next if symlink?(full)
          next unless Dir.exists?(full)
          prune_empty_directories(full)
          begin
            Dir.delete(full) if Dir.empty?(full)
          rescue File::Error | IO::Error
            next
          end
        end
      end

      private def each_project_file(root : String, follow_symlinks : Bool = true, &block : String ->)
        visited = Set(String).new
        visited << Hwaro::Utils::PathUtils.resolved_real_path(root)
        walk_project_files(root, visited, follow_symlinks, &block)
      end

      private def walk_project_files(dir : String, visited : Set(String), follow_symlinks : Bool, &block : String ->)
        Dir.each_child(dir) do |entry|
          next if entry == ".DS_Store"
          full = File.join(dir, entry)
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
            if entry.starts_with?(".") && entry != ".well-known"
              next
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
            walk_project_files(full, visited, follow_symlinks, &block)
          elsif info.file?
            block.call(full)
          end
        end
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

      private def nested_path?(a : String, b : String) : Bool
        a = a.rstrip('/')
        b = b.rstrip('/')
        return false if a.empty? || b.empty?
        # Identical directories also count as overlap — otherwise a
        # source == destination config slips past the overlap refusal and a
        # strip_index_html target can mutate/delete the source tree.
        return true if a == b
        b.starts_with?(a + "/")
      end
    end
  end
end
