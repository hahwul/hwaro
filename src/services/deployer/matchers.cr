# Deployer — `[[deployment.matchers]]` (pattern compilation, per-file
# metadata, cloud metadata uploads, precompressed `.gz` siblings).
#
# Reopens `Services::Deployer`; deployer.cr keeps the result records, the
# three entry points (plan / run / deploy_structured) and per-target
# dispatch. Parts only reopen the class: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Deployer
      private record CompiledMatcher, matcher : Models::DeploymentMatcher, regex : Regex

      # One file the cloud metadata pass re-uploads after the main sync.
      private record MetadataUpload,
        rel : String,
        source : String,
        destination : String,
        matcher : Models::DeploymentMatcher

      # Compile the matchers that do something (`force` or metadata), in
      # config order. An invalid pattern warns and is skipped instead of
      # crashing the deploy.
      private def compile_matchers(deployment : Models::DeploymentConfig) : Array(CompiledMatcher)
        deployment.matchers.compact_map do |matcher|
          next unless matcher.force || sets_metadata?(matcher)
          CompiledMatcher.new(matcher, Regex.new(matcher.pattern))
        rescue ex : ArgumentError
          Logger.warn "Ignoring invalid deployment matcher pattern #{matcher.pattern.inspect}: #{ex.message}"
          nil
        end
      end

      private def force_patterns(matchers : Array(CompiledMatcher)) : Array(Regex)
        matchers.select(&.matcher.force).map(&.regex)
      end

      private def sets_metadata?(matcher : Models::DeploymentMatcher) : Bool
        !!(matcher.cache_control || matcher.content_type || !matcher.gzip.nil?)
      end

      # The first matcher (config order) that sets metadata and whose
      # pattern matches `rel` or `src_rel` — the source spelling, which
      # differs under strip_index_html, judged the same way as `force`.
      # Matchers are not merged: the winner supplies every header.
      private def metadata_matcher(rel : String, matchers : Array(CompiledMatcher), src_rel : String = rel) : Models::DeploymentMatcher?
        matchers.find do |compiled|
          sets_metadata?(compiled.matcher) &&
            (compiled.regex.matches?(rel) || (src_rel != rel && compiled.regex.matches?(src_rel)))
        end.try(&.matcher)
      end

      # The headers a matcher asks for, as the `--dry-run --json` plan lists
      # them.
      private def metadata_headers(matcher : Models::DeploymentMatcher) : Hash(String, String)
        headers = {} of String => String
        matcher.cache_control.try { |value| headers["Cache-Control"] = value }
        matcher.content_type.try { |value| headers["Content-Type"] = value }
        headers["Content-Encoding"] = "gzip" if matcher.gzip
        headers
      end

      # ---- cloud targets (s3:// gs:// az://) ----

      # Every source file a metadata matcher claims, sorted. The main sync
      # already uploaded them; the second pass re-uploads each with headers.
      private def metadata_uploads(url : String, source_dir : String, matchers : Array(CompiledMatcher)) : Array(MetadataUpload)
        uploads = [] of MetadataUpload
        return uploads if matchers.none? { |compiled| sets_metadata?(compiled.matcher) }
        gs = URI.parse(url).scheme == "gs"
        # Every local path gsutil would see starts with the source root.
        if gs && GSUTIL_WILDCARD.matches?(source_dir)
          Logger.warn "deployment.matchers: skipping metadata uploads — gsutil reads [ ] * ? in the source directory #{source_dir} as a wildcard."
          return uploads
        end
        wildcards = [] of String

        each_project_file(source_dir) do |path|
          rel = relative_to(path, source_dir)
          next if rel.empty? || ignored_file?(rel)
          next unless matcher = metadata_matcher(rel, matchers)
          # `gzip = false` alone claims the file but sets no header.
          next if metadata_headers(matcher).empty?
          if gs && GSUTIL_WILDCARD.matches?(rel)
            wildcards << rel
            next
          end
          uploads << MetadataUpload.new(rel, path, cloud_object_url(url, rel), matcher)
        end
        wildcards.sort!.each do |rel|
          Logger.warn "deployment.matchers: skipping metadata upload of #{rel} — gsutil reads [ ] * ? in a file name as a wildcard."
        end
        uploads.sort_by!(&.rel)
      end

      # `gsutil cp` expands these in both the local path and the object URL,
      # and has no escape for them.
      private GSUTIL_WILDCARD = /[\[\]*?]/

      # `aws s3 sync {source}/ {url}` puts `rel` at `{url}/rel`; gsutil and
      # az do the same with their URL/prefix.
      private def cloud_object_url(url : String, rel : String) : String
        "#{url.rstrip('/')}/#{rel}"
      end

      # The CLI argv that uploads `file` as `rel` under `url` with the
      # matcher's headers. `file` is what gets sent: for aws/az with gzip it
      # is an already-compressed copy; gsutil compresses itself (`-Z`).
      private def metadata_upload_argv(url : String, file : String, rel : String, matcher : Models::DeploymentMatcher) : Array(String)
        uri = URI.parse(url)
        case uri.scheme
        when "s3"
          argv = ["aws", "s3", "cp", file, cloud_object_url(url, rel)]
          matcher.cache_control.try { |value| argv.push("--cache-control", value) }
          matcher.content_type.try { |value| argv.push("--content-type", value) }
          argv.push("--content-encoding", "gzip") if matcher.gzip
          argv
        when "gs"
          argv = ["gsutil"]
          matcher.cache_control.try { |value| argv.push("-h", "Cache-Control:#{value}") }
          matcher.content_type.try { |value| argv.push("-h", "Content-Type:#{value}") }
          argv << "cp"
          argv << "-Z" if matcher.gzip
          argv.push(file, cloud_object_url(url, rel))
        else
          # az://container/prefix (`#auto_command_for_url` admits no other
          # scheme) — same container/prefix split as `az storage blob sync`.
          prefix = URI.decode(uri.path.lchop('/')).rstrip('/')
          name = prefix.empty? ? rel : "#{prefix}/#{rel}"
          argv = ["az", "storage", "blob", "upload", "--container-name", uri.host.to_s,
                  "--file", file, "--name", name, "--overwrite"]
          matcher.cache_control.try { |value| argv.push("--content-cache-control", value) }
          matcher.content_type.try { |value| argv.push("--content-type", value) }
          argv.push("--content-encoding", "gzip") if matcher.gzip
          argv
        end
      end

      # aws and az upload bytes as-is, so gzip means compressing first.
      private def compresses_locally?(url : String, matcher : Models::DeploymentMatcher) : Bool
        matcher.gzip == true && URI.parse(url).scheme != "gs"
      end

      # The argv as one shell command line. Every argument goes through
      # `#shell_escape`; the program name is a fixed literal, left bare so
      # cmd.exe still resolves the `.cmd` shims (`az.cmd`, `gsutil.cmd`).
      private def shell_join(argv : Array(String)) : String
        ([argv.first] + argv[1..].map { |arg| shell_escape(arg) }).join(" ")
      end

      # cmd.exe expands `%NAME%` even inside double quotes, so a `%` in a
      # path or header value is judged like one a placeholder brought in.
      # Returns the warning naming the first offending file, or nil.
      private def metadata_percent_warning(url : String, uploads : Array(MetadataUpload)) : String?
        upload = uploads.find { |candidate| metadata_upload_argv(url, candidate.source, candidate.rel, candidate.matcher).any?(&.includes?('%')) }
        return unless upload
        "Metadata upload of #{upload.rel} contains '%', which cmd.exe expands even inside quotes."
      end

      private def log_planned_uploads(uploads : Array(MetadataUpload)) : Nil
        Logger.info "Dry run: would upload #{uploads.size} file(s) with metadata:"
        uploads.each do |upload|
          headers = metadata_headers(upload.matcher).join(", ") { |key, value| "#{key}: #{value}" }
          Logger.info "  #{upload.rel} → #{upload.destination} (#{headers})"
        end
      end

      # Re-upload each matched file with its headers, one CLI call per file.
      private def run_metadata_uploads(target : Models::DeploymentTarget, uploads : Array(MetadataUpload), env : Hash(String, String)) : Nil
        return if uploads.empty?
        url = target.url
        Logger.info "  Uploading #{uploads.size} file(s) with metadata"
        tmp_dir = nil
        begin
          uploads.each_with_index do |upload, idx|
            Logger.progress(idx + 1, uploads.size, "Uploading ")
            file = upload.source
            if compresses_locally?(url, upload.matcher)
              dir = tmp_dir ||= File.join(Dir.tempdir, "hwaro-deploy-#{Random::Secure.hex(8)}").tap { |path| Dir.mkdir(path) }
              # Same basename as the original: aws and az guess the
              # Content-Type from the local file name.
              file = File.join(dir, File.basename(upload.source))
              classify_io_errors(target) { gzip_file(upload.source, file) }
            end
            command = shell_join(metadata_upload_argv(url, file, upload.rel, upload.matcher))
            status, stderr = run_deploy_command(command, env)
            raise_command_failed!(status, stderr, command) unless status.success?
          end
        ensure
          FileUtils.rm_rf(tmp_dir) if tmp_dir
        end
      end

      # ---- file:// targets ----

      # Destination files that get a precompressed `<file>.gz` sibling: the
      # first metadata matcher says `gzip`, the file is not itself a `.gz`,
      # the source does not ship its own `<file>.gz` (that one wins), and
      # the target does not exclude the sibling (excluded paths are never
      # touched at the destination).
      private def gzip_stems(desired : Hash(String, String), source_dir : String, matchers : Array(CompiledMatcher), target : Models::DeploymentTarget) : Array(String)
        return [] of String if matchers.none? { |compiled| compiled.matcher.gzip == true }
        desired.compact_map do |dest_rel, src_path|
          next if dest_rel.ends_with?(".gz") || desired.has_key?("#{dest_rel}.gz")
          next if target_exclude_match?("#{dest_rel}.gz", target)
          dest_rel if gzip_matched?(dest_rel, matchers, relative_to(src_path, source_dir))
        end
      end

      private def gzip_matched?(rel : String, matchers : Array(CompiledMatcher), src_rel : String = rel) : Bool
        metadata_matcher(rel, matchers, src_rel).try(&.gzip) == true
      end

      # Deletes that are the sibling hwaro wrote for a page deleted in the
      # same sync: the stem is deleted too and is gzip-matched. Those go with
      # their page and are not counted against `--max-deletes`; every other
      # `.gz` (another tool's output, a sibling whose page stays) counts.
      private def stale_gzip_siblings(to_delete : Array(String), matchers : Array(CompiledMatcher), target : Models::DeploymentTarget, dest_dir : String) : Int32
        return 0 if matchers.none? { |compiled| compiled.matcher.gzip == true }
        deleted = to_delete.to_set
        to_delete.count do |rel|
          next false unless rel.ends_with?(".gz")
          stem = rel.rchop(".gz")
          next false unless deleted.includes?(stem)
          # A stripped page `foo` was matched by its source spelling.
          gzip_matched?(stem, matchers, stem_source_rel(stem, target, dest_dir))
        end
      end

      private def gzipped_note(sync : DirectorySync) : String
        sync.to_gzip.empty? ? "" : " · #{sync.to_gzip.size} gzipped"
      end

      # A sibling needs (re)writing when it is missing, is not a regular file,
      # or is older than the file it compresses.
      private def gzip_sibling_stale?(dest_path : String) : Bool
        gz = File.info?("#{dest_path}.gz", follow_symlinks: false)
        return true unless gz && gz.file?
        stem = File.info?(dest_path)
        stem.nil? || gz.modification_time < stem.modification_time
      rescue File::Error | IO::Error
        true
      end

      # Compress `src` into `dest` through a temporary sibling, so an
      # interrupted write never leaves a truncated `.gz` that looks fresh.
      private def gzip_file(src : String, dest : String) : Nil
        tmp = "#{dest}.tmp-#{Random::Secure.hex(4)}"
        begin
          File.open(src, "rb") do |input|
            File.open(tmp, "wb") do |output|
              Compress::Gzip::Writer.open(output, level: Compress::Gzip::BEST_COMPRESSION) { |gzip| IO.copy(input, gzip) }
            end
          end
          File.rename(tmp, dest)
        ensure
          File.delete?(tmp)
        end
      end

      # Command-driven targets hand the whole tree to a tool hwaro does not
      # control, so it cannot attach headers to individual files there.
      private def warn_unapplied_matchers(target : Models::DeploymentTarget, deployment : Models::DeploymentConfig) : Nil
        return if deployment.matchers.none? { |matcher| sets_metadata?(matcher) }
        Logger.warn "deployment.matchers: cache_control/content_type/gzip are not applied to command target '#{target.name}' — set headers and compression in the command itself."
      end

      # A local copy has no HTTP headers; only `gzip` (the `.gz` siblings)
      # does anything for a directory target.
      private def warn_local_header_matchers(target : Models::DeploymentTarget, deployment : Models::DeploymentConfig) : Nil
        return if deployment.matchers.none? { |matcher| matcher.cache_control || matcher.content_type }
        Logger.warn "deployment.matchers: cache_control/content_type have no effect on local directory target '#{target.name}' — files on disk carry no HTTP headers; set them in your web server config."
      end
    end
  end
end
