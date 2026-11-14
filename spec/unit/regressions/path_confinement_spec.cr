require "../../spec_helper"
require "../../support/build_helper"

# Path confinement invariants, pinned as properties:
#
#   * every file a build (or importer, exporter, scaffold, deploy) WRITES or
#     DELETES lies inside the directory it is meant for, whatever a
#     non-trusted path component (front matter, file and directory names,
#     data records, taxonomy terms, importer fields, fetched names, cache or
#     state file contents) spells;
#   * every file content can make hwaro READ lies inside the project, and
#     never in `.git/`, `.hwaro/` or the output directory.
#
# Each helper that turns an untrusted component into a path is driven with a
# fixed table of unusual spellings plus a few hundred seeded pseudo-random
# strings over the same alphabet; the end-to-end builds plant a sentinel tree
# next to the project and assert it is byte-for-byte untouched and that none
# of its bytes reach the output.
module ConfineCases
  SEED = 20_261_115_u64

  # Spellings that have broken (or could break) a path builder somewhere.
  FIXED = [
    "..", "../x", "../../etc/passwd", "a/../../x", "a/b/../../../x",
    "..\\x", "a\\..\\..\\x", "\\..\\x",
    "%2e%2e/x", "%2E%2E%2Fx", "..%2fx", "..%2F..%2Fx", "%2e%2e%5cx", "..%5c..%5cx",
    "%252e%252e%252fx", "%252E%252E/x", "..%252f..%252fx", "%25252e%25252e/x",
    "/etc/passwd", "/", "//host/share/x", "\\\\host\\share\\x", "C:\\x", "C:/x", "c:x",
    "~", "~/x", "~root/x", "~/.ssh/id_rsa",
    "", ".", "./", "./.", "...", "....", ". .", ".. ", " ..", "x. ", "x.", "x ", "x...",
    "a" * 300, ("b" * 250 + "/") * 3, ("c" * 120 + "/../") * 4,
    ".HWARO/x", ".Hwaro", ".hwaro/serve/index.html", "PUBLIC/x", "Public/../..",
    ".GIT/config", ".git/config", ".Git/HEAD",
    "\u2215..\u2215x", "..\u2215..\u2215x", "..\uFF0Fx", "\uFF0E\uFF0E/x", "..\u2044x", "..\uFF3Cx",
    "\u2024\u2024/x", "e\u0301", "\u00e9", "cafe\u0301/../..",
    "%00../x", "..\u0000/x", "a\u0000b", "%c0%ae%c0%ae/x", "%e0%80%ae%e0%80%ae/x",
    "a/./b", "a//b", "a/b/", "?x=../..", "#../..",
  ]

  ALPHABET = [
    ".", ".", "..", "/", "/", "\\", "%2e", "%2E", "%2f", "%2F", "%5c", "%252e", "%252f",
    "%25", "~", " ", "a", "Z", "\u2215", "\uFF0F", "\uFF0E", "\u2024", "e\u0301", "\u00e9",
    ":", "\u0000", "%00", ".hwaro", ".git", "public", "PUBLIC", "x" * 40,
  ]

  def self.random(count : Int32 = 300) : Array(String)
    rng = Random::PCG32.new(SEED)
    Array.new(count) do
      String.build do |io|
        (1 + rng.rand(8)).times { io << ALPHABET[rng.rand(ALPHABET.size)] }
      end
    end
  end

  def self.all : Array(String)
    FIXED + random
  end
end

# A fixed lexical root: these helpers never touch the filesystem.
CONFINE_ROOT = File.expand_path(File.join(Dir.tempdir, "confine-root", "public"))

# `File.expand_path` of `relative` under `root` is `root` or below it. A
# string no path can be built from (an embedded NUL) cannot be written
# either, so it counts as confined.
private def confine_within?(relative : String, root : String = CONFINE_ROOT) : Bool
  Hwaro::Utils::PathUtils.within?(File.expand_path(File.join(root, relative)), root)
rescue ArgumentError
  true
end

# Every regular file under `root` (relative path => bytes) plus every
# directory and symlink (with its target), so a before/after comparison sees
# a new, removed, modified or retargeted entry.
private def confine_snapshot(root : String, skip : String? = nil) : Hash(String, String)
  snap = {} of String => String
  # `**` lists a symlink but never descends into a linked directory.
  Dir.glob(File.join(Hwaro::Utils::PathUtils.glob_escape(root), "**", "*"), match: File::MatchOptions::DotFiles) do |full|
    next if skip && (full == skip || full.starts_with?("#{skip}/"))
    info = File.info(full, follow_symlinks: false)
    snap[Path[full].relative_to(root).to_s] = if info.symlink?
                                                "link:#{File.readlink(full)}"
                                              elsif info.directory?
                                                "dir"
                                              else
                                                "file:#{File.read(full)}"
                                              end
  end
  snap
end

# Every file under `dir` whose bytes contain one of `markers`.
private def confine_leaks(dir : String, markers : Array(String)) : Array(String)
  return [] of String unless Dir.exists?(dir)
  Dir.glob(File.join(dir, "**", "*"), match: File::MatchOptions::DotFiles).select do |path|
    File.file?(path) && (body = File.read(path)) && markers.any? { |m| body.includes?(m) }
  end
end

CONFINE_PARENT_CANARY  = "CONFINE-PARENT-CANARY-7f3a"
CONFINE_SIBLING_CANARY = "CONFINE-SIBLING-CANARY-91c2"

# sandbox/ holds the project (`proj/`) and, around it, the sentinel tree a
# build must never touch: a file in the parent and a sibling directory.
private def confine_sandbox(& : String, String ->) : Nil
  Dir.mktmpdir do |sandbox|
    File.write(File.join(sandbox, "secret.txt"), CONFINE_PARENT_CANARY)
    outside = File.join(sandbox, "outside")
    FileUtils.mkdir_p(File.join(outside, "sub"))
    File.write(File.join(outside, "victim.html"), CONFINE_SIBLING_CANARY)
    File.write(File.join(outside, "victim.png"), CONFINE_SIBLING_CANARY)
    File.write(File.join(outside, "victim.json"), CONFINE_SIBLING_CANARY)
    File.write(File.join(outside, "evil.md"), "+++\ntitle = \"#{CONFINE_SIBLING_CANARY}\"\n+++\n#{CONFINE_SIBLING_CANARY}\n")
    File.write(File.join(outside, "sub", "v.txt"), CONFINE_SIBLING_CANARY)
    proj = File.join(sandbox, "proj")
    Dir.mkdir(proj)
    yield sandbox, proj
  end
end

private def confine_write_tree(base : String, files : Hash(String, String)) : Nil
  files.each do |path, body|
    full = File.join(base, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end
end

# `Builder#run` inside `proj` (the working directory a build always has).
private def confine_run_build(proj : String, cache : Bool = false) : Hwaro::Core::Build::Builder
  builder = Hwaro::Core::Build::Builder.new
  Dir.cd(proj) do
    Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
    builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: cache))
  end
  builder
end

# Private path builders, reached the way AGENTS.md describes.
class Hwaro::Services::Importers::Base
  def confine_resolve(output_dir : String, section : String, slug : String) : String?
    resolve_content_path(output_dir, section, slug, quiet: true)
  end

  def confine_filename_component(value : String) : String
    safe_filename_component(value)
  end
end

class Hwaro::Content::Search
  def self.confine_shard_file_name(id : String) : String
    shard_file_name(id)
  end

  def self.confine_remove_stale_shard(shards_dir : String, id : String) : Nil
    remove_stale_shard(shards_dir, id)
  end
end

class Hwaro::Content::Seo::OgImage
  def self.confine_prune(img_dir : String, output_dir : String, old_entries : Hash(String, String)) : Nil
    prune_orphaned_images(img_dir, output_dir, old_entries, {} of String => String, false)
  end
end

class Hwaro::Core::Build::Builder
  def confine_delete_orphaned(paths : Array(String), output_dir : String) : Nil
    delete_orphaned_outputs(paths, output_dir)
  end

  def confine_url_output_path(url : String) : String?
    url_output_path(url)
  end
end

CONFINE_BASE_CONFIG = <<-TOML
  title = "Confine"
  base_url = "http://localhost"

  [[taxonomies]]
  name = "tags"
  feed = true
  paginate_by = 1

  [search]
  enabled = true

  [sitemap]
  enabled = true

  [feeds]
  enabled = true

  [content.files]
  allow_extensions = ["json", "txt"]

  [[content.generate]]
  source = "items.list"
  section = "gen"
  slug = "s"
  title = "t"
  body = "b"
  TOML

CONFINE_TEMPLATES = {
  "page.html"          => "<main>{{ page.title }}|{{ content }}</main>",
  "section.html"       => "<main>{{ section.title }}|{{ content }}</main>",
  "index.html"         => "<main>home|{{ content }}</main>",
  "taxonomy.html"      => "<main>tax</main>",
  "taxonomy_term.html" => "<main>term</main>",
  "page.json.jinja"    => %({"title": {{ page.title | tojson }}}),
  "page.txt.jinja"     => "{{ page.title }}",
}

describe "Path confinement" do
  describe "untrusted component -> output path helpers" do
    it "split_safe_segments refuses, or yields segments that stay under the root" do
      ConfineCases.all.each do |value|
        segments, refused = Hwaro::Utils::PathUtils.split_safe_segments(value)
        next if refused
        segments.each do |segment|
          segment.should_not contain("/")
          segment.should_not contain("\\")
          segment.rstrip(". ").empty?.should be_false
        end
        confine_within?(segments.join("/")).should be_true, "split_safe_segments(#{value.inspect}) escaped: #{segments.inspect}"
      end
    end

    it "the render phase's url_output_path never names a path outside the output directory" do
      builder = Hwaro::Core::Build::Builder.new
      ConfineCases.all.each do |value|
        if path = builder.confine_url_output_path(value)
          confine_within?(path).should be_true, "url_output_path(#{value.inspect}) = #{path.inspect}"
        end
      end
    end

    it "sanitize_path (neutralize policy) always stays under the root" do
      ConfineCases.all.each do |value|
        clean = Hwaro::Utils::PathUtils.sanitize_path(value)
        confine_within?(clean).should be_true, "sanitize_path(#{value.inspect}) = #{clean.inspect}"
      end
    end

    it "output_file_key and alias_refusal agree with the refuse policy" do
      ConfineCases.all.each do |value|
        if key = Hwaro::Utils::PathUtils.output_file_key(value)
          confine_within?(key).should be_true, "output_file_key(#{value.inspect}) = #{key.inspect}"
        end
        next if Hwaro::Utils::PathUtils.alias_refusal(value)
        segments, refused = Hwaro::Utils::PathUtils.split_safe_segments(value.lchop("/"))
        refused.should be_false
        confine_within?(segments.join("/")).should be_true
      end
    end

    it "OutputGuard.safe_output_path answers nil or a path inside the output directory" do
      ConfineCases.all.each do |value|
        candidate = "#{CONFINE_ROOT}/#{value}"
        with_captured_log do
          if safe = Hwaro::Utils::OutputGuard.safe_output_path(candidate, CONFINE_ROOT)
            Hwaro::Utils::PathUtils.within?(safe, CONFINE_ROOT).should be_true, "safe_output_path(#{candidate.inspect}) = #{safe.inspect}"
          end
        end
      end
    end

    it "slugify (taxonomy terms, [[content.generate]] slugs) never yields a separator or a dot-only name" do
      ConfineCases.all.each do |value|
        slug = Hwaro::Utils::TextUtils.slugify(value)
        slug.should_not contain("/")
        slug.should_not contain("\\")
        slug.should_not contain("\u0000")
        (slug.empty? || !slug.rstrip(". ").empty?).should be_true, "slugify(#{value.inspect}) = #{slug.inspect}"
        confine_within?(slug).should be_true
      end
    end

    it "OG image slugs of publishable pages stay one file name inside the image directory" do
      img_dir = File.join(CONFINE_ROOT, "og-images")
      ConfineCases.all.each do |value|
        page = Hwaro::Models::Page.new("p.md")
        page.url = "/#{value}/"
        # Only a page whose URL publishes reaches the generator (a refused URL
        # is output_suppressed, which `eligible_for_auto_image?` checks).
        next unless Hwaro::Utils::PathUtils.output_file_key(page.url)
        slug = Hwaro::Content::Seo::OgImage.slug_for(page, {} of String => String)
        slug.should_not contain("/")
        slug.should_not contain("\\")
        slug.rstrip(". ").empty?.should be_false
        confine_within?("#{slug}.png", img_dir).should be_true, "slug_for(#{page.url.inspect}) = #{slug.inspect}"
      end
    end

    it "importer destinations (section + slug from the export) stay inside the import target" do
      importer = Hwaro::Services::Importers::WordPressImporter.new
      cases = ConfineCases.all
      with_captured_log do
        cases.each_with_index do |section, i|
          slug = cases[(i * 7 + 3) % cases.size]
          {section, "posts"}.each do |sec|
            {slug, section, "ok"}.each do |sl|
              if path = importer.confine_resolve(CONFINE_ROOT, sec, sl)
                Hwaro::Utils::PathUtils.within?(File.expand_path(path), CONFINE_ROOT).should be_true,
                  "resolve_content_path(#{sec.inspect}, #{sl.inspect}) = #{path.inspect}"
              end
            end
          end
          name = importer.confine_filename_component(section)
          name.should_not contain("/")
          name.should_not contain("\\")
          (name.empty? || !{".", ".."}.includes?(name)).should be_true
        end
      end
    end

    it "remote scaffold entries map to paths inside the scaffold target" do
      ConfineCases.all.each do |value|
        {"content/#{value}.md", "templates/#{value}", "templates/shortcodes/#{value}",
         "static/#{value}", "archetypes/#{value}", "data/#{value}", value}.each do |entry|
          next unless mapped = Hwaro::Services::Scaffolds::Remote.classify(entry)
          _category, key = mapped
          confine_within?(key).should be_true, "classify(#{entry.inspect}) = #{mapped.inspect}"
        end
      end
    end

    it "include_code / include_md paths stay inside the project" do
      ConfineCases.all.each do |value|
        relative = begin
          Hwaro::Content::Processors::Includes.relative_path(value)
        rescue Hwaro::Content::Processors::Includes::Error
          next
        end
        confine_within?(relative).should be_true, "Includes.relative_path(#{value.inspect}) = #{relative.inspect}"
      end
    end
  end

  describe "deletes driven by cache / state file contents" do
    it "the search shard sweep never deletes outside the shard directory" do
      confine_sandbox do |sandbox, proj|
        shards = File.join(proj, "public", "search")
        FileUtils.mkdir_p(shards)
        ids = ConfineCases.all + ["../../../outside/victim", "../../../outside/sub/../victim", "..\\..\\..\\outside\\victim"]
        # Plant a victim exactly where a naive join of each manifest id
        # lands, whenever that is outside the project but inside the sandbox.
        ids.each do |id|
          naive = File.expand_path(File.join(shards, Hwaro::Content::Search.confine_shard_file_name(id))) rescue next
          next if Hwaro::Utils::PathUtils.within?(naive, proj) || !Hwaro::Utils::PathUtils.within?(naive, sandbox)
          begin
            FileUtils.mkdir_p(File.dirname(naive))
            File.write(naive, CONFINE_SIBLING_CANARY) unless File.exists?(naive)
          rescue File::Error
          end
        end
        before = confine_snapshot(sandbox, skip: proj)
        before.should contain({"outside/victim.json", "file:#{CONFINE_SIBLING_CANARY}"})
        ids.each { |id| Hwaro::Content::Search.confine_remove_stale_shard(shards, id) }
        Dir.exists?(shards).should be_true
        confine_snapshot(sandbox, skip: proj).should eq(before)
      end
    end

    it "the OG image prune never deletes outside the output directory" do
      confine_sandbox do |sandbox, proj|
        output = File.join(proj, "public")
        img_dir = File.join(output, "og-images")
        FileUtils.mkdir_p(img_dir)
        before = confine_snapshot(sandbox, skip: proj)
        before.should contain({"outside/victim.png", "file:#{CONFINE_SIBLING_CANARY}"})
        # The manifest is a state file in the output tree (and a static file
        # can ship one): its slugs are read back exactly as the build does.
        slugs = ConfineCases.all + ["../../../outside/victim", "../../../secret", "..%2f..%2f..%2foutside%2fvictim"]
        manifest = File.join(img_dir, ".og_manifest.json")
        File.write(manifest, {"config_hash" => "x", "entries" => slugs.to_h { |slug| {slug, "h"} }}.to_json)
        _, entries = Hwaro::Content::Seo::OgImage.load_manifest(manifest)
        entries.size.should be > 300
        Dir.cd(proj) { Hwaro::Content::Seo::OgImage.confine_prune(img_dir, output, entries) }
        confine_snapshot(sandbox, skip: proj).should eq(before)
      end
    end

    it "Finalize's orphan delete refuses paths outside the output directory, including through a symlinked parent" do
      posix_only!("symlinks")
      confine_sandbox do |sandbox, proj|
        output = File.join(proj, "public")
        FileUtils.mkdir_p(output)
        File.symlink(File.join(sandbox, "outside"), File.join(output, "escape"))
        before = confine_snapshot(sandbox, skip: proj)
        candidates = [
          File.join(sandbox, "outside", "victim.html"),
          File.join(sandbox, "secret.txt"),
          File.join(output, "..", "..", "secret.txt"),
          File.join(output, "..", "..", "outside", "victim.html"),
          File.join(output, "escape", "victim.html"),
          File.join(output, "escape", "sub", "v.txt"),
          "public/../../secret.txt",
          "public/escape/victim.png",
        ]
        builder = Hwaro::Core::Build::Builder.new
        Dir.cd(proj) do
          builder.confine_delete_orphaned(candidates, "public")
          builder.prune_unclaimed_outputs(candidates, "public")
        end
        confine_snapshot(sandbox, skip: proj).should eq(before)
      end
    end

    it "a warm --cache build never deletes an output path forged in the cache file" do
      confine_sandbox do |sandbox, proj|
        confine_write_tree(proj, {"config.toml" => BASIC_CONFIG})
        confine_write_tree(File.join(proj, "templates"), CONFINE_TEMPLATES)
        confine_write_tree(File.join(proj, "content"), {
          "keep.md" => "+++\ntitle = \"Keep\"\n+++\nkeep\n",
          "gone.md" => "+++\ntitle = \"Gone\"\n+++\ngone\n",
        })
        with_captured_log { confine_run_build(proj, cache: true) }
        cache_file = File.join(proj, Hwaro::Core::Build::Cache::CACHE_FILE)
        File.exists?(cache_file).should be_true

        victim = File.join(sandbox, "outside", "victim.html")
        json = JSON.parse(File.read(cache_file)).as_h
        entries = json["entries"].as_a.map do |entry|
          h = entry.as_h.dup
          if h["path"]?.try(&.as_s?).try(&.includes?("gone.md"))
            h["output_path"] = JSON::Any.new(victim)
            h["output_paths"] = JSON::Any.new([JSON::Any.new(victim), JSON::Any.new("../secret.txt")])
            h["derived_paths"] = JSON::Any.new([JSON::Any.new("public/../../outside/victim.png")])
          end
          JSON::Any.new(h)
        end
        json["entries"] = JSON::Any.new(entries)
        metadata = json["metadata"].as_h.dup
        metadata["generated_outputs"] = JSON::Any.new(["../../outside/victim.json", "../../secret.txt", "../outside/sub/v.txt"].map { |s| JSON::Any.new(s) })
        json["metadata"] = JSON::Any.new(metadata)
        File.write(cache_file, json.to_json)

        before = confine_snapshot(sandbox, skip: proj)
        File.delete(File.join(proj, "content", "gone.md"))
        with_captured_log { confine_run_build(proj, cache: true) }
        File.exists?(File.join(proj, "public", "keep", "index.html")).should be_true
        confine_snapshot(sandbox, skip: proj).should eq(before)
      end
    end

    it "sweep_dead_temps does not follow a symlinked directory out of the output tree" do
      posix_only!("symlinks")
      confine_sandbox do |sandbox, proj|
        output = File.join(proj, "public")
        FileUtils.mkdir_p(output)
        dead_pid = 999_999_999
        orphan_inside = File.join(output, "hwaro-#{dead_pid}-1.tmp")
        File.write(orphan_inside, "x")
        outside_temp = File.join(sandbox, "outside", "hwaro-#{dead_pid}-2.tmp")
        File.write(outside_temp, CONFINE_SIBLING_CANARY)
        File.symlink(File.join(sandbox, "outside"), File.join(output, "escape"))
        before = confine_snapshot(sandbox, skip: proj)
        Hwaro::Utils::FileSafe.sweep_dead_temps(output)
        File.exists?(orphan_inside).should be_false
        confine_snapshot(sandbox, skip: proj).should eq(before)
      end
    end

    it "tool unused-assets --delete removes links, never what a link or a linked directory holds" do
      posix_only!("symlinks")
      confine_sandbox do |sandbox, proj|
        confine_write_tree(proj, {"static/orphan.png" => "png", "content/post.md" => "+++\ntitle = \"P\"\n+++\n", "templates/page.html" => "x"})
        File.symlink(File.join(sandbox, "outside", "victim.png"), File.join(proj, "static", "linked.png"))
        File.symlink(File.join(sandbox, "outside"), File.join(proj, "static", "linkdir"))
        File.symlink(File.join(sandbox, "outside"), File.join(proj, "content", "linkdir"))
        before = confine_snapshot(sandbox, skip: proj)
        Dir.cd(proj) do
          service = Hwaro::Services::UnusedAssets.new
          files = service.run.unused_files
          files.should contain("static/orphan.png")
          files.none?(&.includes?("linkdir")).should be_true
          with_captured_log { service.delete_unused(files) }
        end
        File.exists?(File.join(proj, "static", "orphan.png")).should be_false
        confine_snapshot(sandbox, skip: proj).should eq(before)
      end
    end
  end

  describe "content-chosen reads" do
    it "include reads refuse everything outside the project, .git/, .hwaro/ and the output directory" do
      posix_only!("symlinks")
      confine_sandbox do |sandbox, proj|
        Dir.cd(proj) do
          confine_write_tree(proj, {
            ".git/config"         => "secret",
            ".hwaro/serve/a.html" => "secret",
            "public/a.html"       => "secret",
            "ok.txt"              => "fine",
          })
          File.symlink(File.join(sandbox, "secret.txt"), "to_parent.txt")
          File.symlink(File.join(sandbox, "outside"), "to_sibling")
          File.symlink(File.join(proj, ".git", "config"), "to_git.txt")
          File.symlink(File.join(proj, ".hwaro", "serve", "a.html"), "to_hwaro.html")
          File.symlink(File.join(proj, "public", "a.html"), "to_public.html")
          File.symlink(File.join(proj, ".git"), "gitdir")

          refused = ["to_parent.txt", "to_sibling/victim.html", "to_sibling/sub/v.txt", "to_git.txt",
                     "to_hwaro.html", "to_public.html", "gitdir/config", ".git/config", ".GIT/config",
                     ".hwaro/serve/a.html", "public/a.html"]
          refused.each do |rel|
            expect_raises(Hwaro::Content::Processors::Includes::Error) do
              Hwaro::Content::Processors::Includes.read(rel, "public")
            end
          end
          (ConfineCases.all + ["../secret.txt", "../outside/victim.html"]).each do |value|
            relative = Hwaro::Content::Processors::Includes.relative_path(value) rescue next
            begin
              body = Hwaro::Content::Processors::Includes.read(relative, "public")
              body.should_not contain(CONFINE_PARENT_CANARY)
              body.should_not contain(CONFINE_SIBLING_CANARY)
              body.should_not eq("secret")
            rescue Hwaro::Content::Processors::Includes::Error
            end
          end
          Hwaro::Content::Processors::Includes.read("ok.txt", "public").should eq("fine")
        end
      end
    end

    it "the WordPress importer resolves no external entity or DTD" do
      confine_sandbox do |sandbox, proj|
        dtd = File.join(sandbox, "outside", "x.dtd")
        File.write(dtd, %(<!ENTITY leak "#{CONFINE_SIBLING_CANARY}">))
        out_dir = File.join(proj, "content")
        {
          %(<!DOCTYPE rss SYSTEM "file://#{dtd}">),
          %(<!DOCTYPE rss [<!ENTITY leak SYSTEM "file://#{File.join(sandbox, "secret.txt")}">]>),
          %(<!DOCTYPE rss [<!ENTITY % ext SYSTEM "file://#{dtd}"> %ext;]>),
        }.each_with_index do |doctype, i|
          wxr = File.join(sandbox, "export#{i}.xml")
          File.write(wxr, <<-XML)
            <?xml version="1.0" encoding="UTF-8"?>
            #{doctype}
            <rss version="2.0" xmlns:wp="http://wordpress.org/export/1.2/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
            <channel><item>
              <title>T &leak;</title>
              <wp:post_name>p#{i}</wp:post_name>
              <wp:status>publish</wp:status>
              <wp:post_type>post</wp:post_type>
              <content:encoded>body &leak;</content:encoded>
            </item></channel></rss>
            XML
          with_captured_log do
            Hwaro::Services::Importers::WordPressImporter.new.run(
              Hwaro::Config::Options::ImportOptions.new(source_type: "wordpress", path: wxr, output_dir: out_dir))
          end
        end
        confine_leaks(out_dir, [CONFINE_PARENT_CANARY, CONFINE_SIBLING_CANARY]).should be_empty
      end
    end
  end

  describe "end to end" do
    it "a build of hostile content leaves the tree around the project untouched and publishes none of it" do
      posix_only!("symlinks, and `\\` in file names")
      confine_sandbox do |sandbox, proj|
        hostile_paths = ["../../outside/pwn", "..\\..\\outside\\pwn", "%2e%2e/%2e%2e/outside/pwn",
                         "%252e%252e/%252e%252e/outside/pwn", "/../../outside/pwn", "~/pwn",
                         "..%2f..%2foutside%2fpwn", "\uFF0E\uFF0E/\uFF0E\uFF0E/outside/pwn", "PUBLIC/../../outside/pwn"]
        content = {
          "_index.md" => "+++\ntitle = \"Home\"\n+++\n",
          "ok.md"     => "+++\ntitle = \"OK\"\n+++\nok\n",
          "raw.json"  => %({"raw": true}),
          "notes.txt" => "raw text",
        }
        hostile_paths.each_with_index do |value, i|
          v = value.gsub("\\", "\\\\")
          content["slug#{i}.md"] = "+++\ntitle = \"S#{i}\"\nslug = \"#{v}\"\n+++\nx\n"
          content["path#{i}.md"] = "+++\ntitle = \"P#{i}\"\npath = \"#{v}\"\noutputs = [\"json\", \"txt\"]\n+++\nx\n"
          content["redir#{i}.md"] = "+++\ntitle = \"R#{i}\"\npath = \"#{v}-r\"\nredirect_to = \"/ok/\"\n+++\n"
          content["bundle#{i}/index.md"] = "+++\ntitle = \"B#{i}\"\npath = \"#{v}-b\"\n+++\n![x](asset.txt)\n"
          content["bundle#{i}/asset.txt"] = "asset"
        end
        aliases = hostile_paths.flat_map { |v| [v, "#{v}/", "#{v}.html", "/#{v}/index.html"] }
        content["aliased.md"] = "+++\ntitle = \"A\"\naliases = #{aliases.to_json}\n+++\n"
        content["tagged.md"] = "+++\ntitle = \"T\"\ntags = #{hostile_paths.to_json}\n+++\n"
        # Hostile file and directory NAMES (the URL comes from them).
        content["%2e%2e%2f%2e%2e%2foutside%2fpwn-name.md"] = "+++\ntitle = \"N1\"\n+++\n"
        content["..\\..\\outside\\pwn-name2.md"] = "+++\ntitle = \"N2\"\n+++\n"
        content["%252e%252e/x.md"] = "+++\ntitle = \"N3\"\n+++\n"
        content["... /x.md"] = "+++\ntitle = \"N4\"\n+++\n"

        confine_write_tree(proj, {"config.toml" => CONFINE_BASE_CONFIG})
        confine_write_tree(File.join(proj, "templates"), CONFINE_TEMPLATES)
        confine_write_tree(File.join(proj, "content"), content)
        confine_write_tree(File.join(proj, "data"), {
          "items.json" => {"list" => hostile_paths.map_with_index { |v, i| {"s" => "#{v}-g#{i}", "t" => "G#{i}", "b" => "g"} }}.to_json,
        })
        confine_write_tree(File.join(proj, "static"), {"plain.txt" => "plain"})
        # Symlinks INSIDE the project pointing at the sentinel tree.
        File.symlink(File.join(sandbox, "secret.txt"), File.join(proj, "static", "leak.txt"))
        File.symlink(File.join(sandbox, "outside"), File.join(proj, "static", "leakdir"))
        File.symlink(File.join(sandbox, "outside", "evil.md"), File.join(proj, "content", "evil.md"))
        File.symlink(File.join(sandbox, "outside"), File.join(proj, "content", "linked"))
        File.symlink(File.join(sandbox, "outside", "victim.json"), File.join(proj, "content", "rawlink.json"))
        File.symlink(File.join(sandbox, "secret.txt"), File.join(proj, "content", "bundle0", "leak.txt"))

        before = confine_snapshot(sandbox, skip: proj)
        markers = [CONFINE_PARENT_CANARY, CONFINE_SIBLING_CANARY]
        2.times do |round|
          with_captured_log { confine_run_build(proj, cache: round == 1) }
          File.read(File.join(proj, "public", "ok", "index.html")).should contain("OK")
          File.exists?(File.join(proj, "public", "raw.json")).should be_true
          confine_snapshot(sandbox, skip: proj).should eq(before)
          confine_leaks(File.join(proj, "public"), markers).should be_empty
          confine_leaks(File.join(proj, ".hwaro"), markers).should be_empty
        end
      end
    end

    it "deploying to a directory never writes or deletes through a symlink already in the destination" do
      posix_only!("symlinks")
      confine_sandbox do |sandbox, proj|
        src = File.join(proj, "public")
        confine_write_tree(src, {"index.html" => "home", "sub/v.txt" => "new", "victim.html" => "new"})
        dest = File.join(proj, "deploy")
        FileUtils.mkdir_p(dest)
        File.symlink(File.join(sandbox, "outside"), File.join(dest, "sub"))
        File.symlink(File.join(sandbox, "outside", "victim.html"), File.join(dest, "victim.html"))
        File.symlink(File.join(sandbox, "outside"), File.join(dest, "stale"))
        File.symlink(File.join(sandbox, "secret.txt"), File.join(dest, "stale.txt"))
        before = confine_snapshot(sandbox, skip: proj)

        config = Hwaro::Models::Config.new
        target = Hwaro::Models::DeploymentTarget.new
        target.name = "local"
        target.url = dest
        config.deployment.targets << target
        with_captured_log do
          Hwaro::Services::Deployer.new.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["local"]), config)
        end

        File.read(File.join(dest, "sub", "v.txt")).should eq("new")
        confine_snapshot(sandbox, skip: proj).should eq(before)
      end
    end
  end
end
