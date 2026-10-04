# hwaro turns file paths into URLs, output paths and cache keys as
# `/`-separated strings (`"/" + Path[f].relative_to("content").to_s`,
# `File.join(output_dir, url)`, …). On Windows the stdlib builds those paths
# with `\`, which leaked into generated links and broke every comparison
# against a `/` path.
#
# Rather than route ~400 call sites through a helper, the path-producing
# stdlib methods return `/` on Windows. Every Windows file API accepts `/`,
# and `\` can't appear in a Windows file name, so the swap is lossless.
# Compiled out everywhere else.
module Hwaro::WindowsPaths
  # `\` to `/`, except for an extended-length path (`\\?\C:\...`): Windows
  # passes those to the filesystem verbatim, so `/` there is not a separator.
  def self.to_slash(path : String) : String
    path.starts_with?("\\\\?\\") ? path : path.gsub('\\', '/')
  end
end

{% if flag?(:windows) %}
  lib LibC
    fun GetFinalPathNameByHandleW(hFile : HANDLE, lpszFilePath : LPWSTR, cchFilePath : DWORD, dwFlags : DWORD) : DWORD
  end

  module Hwaro::WindowsPaths
    # The path the OS itself resolves `path` to — every symlink and junction
    # along it followed, short names expanded. Raises `File::Error` when it
    # does not exist.
    #
    # The API answers in extended-length form (`\\?\C:\...`). The prefix is
    # dropped only when the ordinary spelling resolves to the very same path:
    # without it Win32 trims a trailing dot or space and applies MAX_PATH. A
    # kept prefix makes a containment check against an unprefixed root fail,
    # which is the safe direction.
    def self.final_path(path : String) : String
      final = extended_final_path(path)
      ordinary = if final.starts_with?("\\\\?\\UNC\\")
                   "\\\\#{final[8..]}"
                 elsif final.starts_with?("\\\\?\\")
                   final[4..]
                 end
      return final unless ordinary

      begin
        extended_final_path(ordinary) == final ? ordinary : final
      rescue ::File::Error
        final
      end
    end

    private def self.extended_final_path(path : String) : String
      handle = LibC.CreateFileW(Crystal::System.to_wstr(path), LibC::FILE_READ_ATTRIBUTES,
        LibC::DEFAULT_SHARE_MODE, nil, LibC::OPEN_EXISTING, LibC::FILE_FLAG_BACKUP_SEMANTICS,
        LibC::HANDLE.null)
      if handle == LibC::INVALID_HANDLE_VALUE
        raise ::File::Error.from_winerror("Error resolving real path", file: path)
      end

      begin
        Crystal::System.retry_wstr_buffer do |buffer, small_buf|
          len = LibC.GetFinalPathNameByHandleW(handle, buffer, buffer.size, 0)
          if 0 < len < buffer.size
            break String.from_utf16(buffer[0, len])
          elsif small_buf && len > 0
            next len
          else
            raise ::File::Error.from_winerror("Error resolving real path", file: path)
          end
        end
      ensure
        LibC.CloseHandle(handle)
      end
    end
  end

  class File
    def self.join(*parts : String | Path) : String
      Hwaro::WindowsPaths.to_slash(previous_def)
    end

    def self.join(parts : Enumerable) : String
      Hwaro::WindowsPaths.to_slash(previous_def)
    end

    def self.expand_path(path : Path | String, dir = nil, *, home = false) : String
      Hwaro::WindowsPaths.to_slash(previous_def)
    end

    # Not `previous_def`: the stdlib's Windows `realpath` resolves a link only
    # in the *last* component, so a path through a symlinked directory
    # (`static/vendor/x` with `vendor -> C:\elsewhere`) came back unresolved
    # and passed every "real path still under the project?" check that keeps
    # symlinked files from being copied into the site.
    def self.realpath(path : Path | String) : String
      Hwaro::WindowsPaths.to_slash(Hwaro::WindowsPaths.final_path(path.to_s))
    end
  end

  class Dir
    def self.current : String
      Hwaro::WindowsPaths.to_slash(previous_def)
    end

    def self.tempdir : String
      Hwaro::WindowsPaths.to_slash(previous_def)
    end
  end

  struct Path
    # `relative_to`, `join`, `normalize`, `expand`, … all build `\` names on
    # Windows; every one of them reaches callers through `to_s`.
    def to_s : String
      Hwaro::WindowsPaths.to_slash(previous_def)
    end
  end
{% end %}
