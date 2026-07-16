require "json"
require "digest/sha1"
require "../../models/config"
require "../../models/site"
require "../../utils/logger"

module Hwaro
  module Content
    module Seo
      class Pwa
        def self.generate(site : Models::Site, output_dir : String, verbose : Bool = false)
          return unless site.config.pwa.enabled

          generate_manifest(site, output_dir, verbose)
          generate_service_worker(site, output_dir, verbose)
        end

        private def self.generate_manifest(site : Models::Site, output_dir : String, verbose : Bool)
          config = site.config
          pwa = config.pwa

          icons = pwa.icons.map do |icon_path|
            size = icon_size(icon_path, output_dir)
            url_path = config.with_base_path(normalize_icon_path(icon_path))
            {
              "src"   => url_path,
              "sizes" => size,
              "type"  => mime_type_for(icon_path),
            }
          end

          manifest = JSON.build do |json|
            json.object do
              json.field "name", pwa.name || config.title
              json.field "short_name", pwa.short_name || pwa.name || config.title
              json.field "description", config.description unless config.description.empty?
              json.field "start_url", config.with_base_path(pwa.start_url)
              json.field "display", pwa.display
              json.field "theme_color", pwa.theme_color
              json.field "background_color", pwa.background_color

              unless icons.empty?
                json.field "icons" do
                  json.array do
                    icons.each do |icon|
                      json.object do
                        json.field "src", icon["src"]
                        json.field "sizes", icon["sizes"]
                        json.field "type", icon["type"]
                      end
                    end
                  end
                end
              end
            end
          end

          path = File.join(output_dir, "manifest.json")
          Hwaro::Utils::FileSafe.atomic_write(path, manifest)
          Logger.action :create, path if verbose
          Logger.info "  Generated manifest.json"
        end

        private def self.generate_service_worker(site : Models::Site, output_dir : String, verbose : Bool)
          config = site.config
          pwa = config.pwa

          # Resolve the launch URL against base_url's path so the precache key
          # and the navigation fallback match what the page actually loads from
          # on a subpath deployment (e.g. `/myrepo/` rather than `/`).
          resolved_start = config.with_base_path(pwa.start_url)

          # Build precache URL list (each entry is a site-internal root-relative
          # path that must carry the subpath prefix, same as start_url).
          base_path = config.base_path
          precache_urls = pwa.precache_urls.map { |u| config.with_base_path(u) }
          precache_urls << resolved_start unless precache_urls.includes?(resolved_start)
          if offline = pwa.offline_page
            resolved_offline = config.with_base_path(offline)
            precache_urls << resolved_offline unless precache_urls.includes?(resolved_offline)
          end

          # cache.addAll() is all-or-nothing: a single 404 aborts the whole
          # service-worker install. Drop any site-internal precache URL whose
          # resolved output file does not exist (external http(s):// URLs are
          # not our files, so we trust them) but always keep the launch URL.
          precache_urls = precache_urls.select do |u|
            next true if external_url?(u)
            next true if u == resolved_start
            if precache_file_exists?(u, output_dir, base_path)
              true
            else
              Logger.warn "PWA: precache URL #{u.inspect} has no matching output file — dropping it from sw.js precache (cache.addAll is all-or-nothing)"
              false
            end
          end

          precache_json = precache_urls.map(&.inspect).join(",\n  ")

          # The navigation fallback must point at a page that actually exists,
          # otherwise the offline experience breaks. Fall back to the launch URL
          # when offline_page resolves to nothing on disk.
          offline_url = if op = pwa.offline_page
                          resolved_offline = config.with_base_path(op)
                          if external_url?(resolved_offline) || precache_file_exists?(resolved_offline, output_dir, base_path)
                            resolved_offline.inspect
                          else
                            Logger.warn "PWA: offline_page #{resolved_offline.inspect} has no matching output file — falling back to start_url #{resolved_start.inspect}"
                            resolved_start.inspect
                          end
                        else
                          resolved_start.inspect
                        end
          root_url = resolved_start.inspect
          # Derive the cache name from the precached URLs AND the bytes of the
          # files they reference, rather than the build clock. Identical content
          # yields a byte-identical sw.js across builds (determinism), while an
          # edit to any precached page/asset changes the hash and busts the
          # cache on deploy (correct invalidation). The PWA hook runs after the
          # render/write phase, so the precached output files already exist.
          cache_hash = Digest::SHA1.hexdigest do |ctx|
            ctx.update(pwa.cache_strategy)
            precache_urls.each do |u|
              ctx.update("\n")
              ctx.update(u)
              next if external_url?(u)
              fpath = precache_file_path(u, output_dir, base_path)
              ctx.update(File.read(fpath)) if File.file?(fpath)
            end
          end
          cache_version = cache_hash[0, 12]

          fetch_handler = case pwa.cache_strategy
                          when "network-first"
                            network_first_handler(offline_url, root_url)
                          when "stale-while-revalidate"
                            stale_while_revalidate_handler(offline_url, root_url)
                          else
                            cache_first_handler(offline_url, root_url)
                          end

          sw_content = <<-JS
            const CACHE_NAME = 'hwaro-#{cache_version}';
            const PRECACHE_URLS = [
              #{precache_json}
            ];

            self.addEventListener('install', event => {
              event.waitUntil(
                caches.open(CACHE_NAME).then(cache => cache.addAll(PRECACHE_URLS))
              );
            });

            self.addEventListener('activate', event => {
              event.waitUntil(
                caches.keys().then(names =>
                  Promise.all(
                    names.filter(name => name !== CACHE_NAME).map(name => caches.delete(name))
                  )
                )
              );
            });

            #{fetch_handler}
            JS

          path = File.join(output_dir, "sw.js")
          Hwaro::Utils::FileSafe.atomic_write(path, sw_content)
          Logger.action :create, path if verbose
          Logger.info "  Generated sw.js"
        end

        # --- Fetch handler strategies ---

        private def self.cache_first_handler(offline_url : String, root_url : String) : String
          <<-JS
            self.addEventListener('fetch', event => {
              if (event.request.mode === 'navigate') {
                event.respondWith(
                  fetch(event.request).catch(() =>
                    caches.match(#{offline_url}).then(cached => cached || caches.match(#{root_url}))
                  )
                );
                return;
              }
              event.respondWith(
                caches.match(event.request).then(cached =>
                  cached || fetch(event.request).then(response => {
                    if (response.ok && response.type === 'basic') {
                      const clone = response.clone();
                      caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
                    }
                    return response;
                  }).catch(() => caches.match(#{offline_url}))
                )
              );
            });
            JS
        end

        private def self.network_first_handler(offline_url : String, root_url : String) : String
          <<-JS
            self.addEventListener('fetch', event => {
              event.respondWith(
                fetch(event.request).then(response => {
                  if (response.ok && response.type === 'basic') {
                    const clone = response.clone();
                    caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
                  }
                  return response;
                }).catch(() =>
                  caches.match(event.request).then(cached =>
                    cached || (event.request.mode === 'navigate'
                      ? caches.match(#{offline_url}).then(offline => offline || caches.match(#{root_url}))
                      : undefined)
                  )
                )
              );
            });
            JS
        end

        private def self.stale_while_revalidate_handler(offline_url : String, root_url : String) : String
          <<-JS
            self.addEventListener('fetch', event => {
              event.respondWith(
                caches.match(event.request).then(cached => {
                  const fetchPromise = fetch(event.request).then(response => {
                    if (response.ok && response.type === 'basic') {
                      const clone = response.clone();
                      caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
                    }
                    return response;
                  }).catch(() => {
                    if (event.request.mode === 'navigate') {
                      return caches.match(#{offline_url}).then(cached => cached || caches.match(#{root_url}));
                    }
                    return undefined;
                  });
                  return cached || fetchPromise;
                })
              );
            });
            JS
        end

        # True for external absolute URLs we don't control (no local file to
        # validate or hash).
        private def self.external_url?(url : String) : Bool
          url.starts_with?("http://") || url.starts_with?("https://")
        end

        # Map a site-internal (possibly base_path-prefixed) URL to the output
        # file it should resolve to: strip base_path, drop the leading slash,
        # join under output_dir, and append index.html for directory-like URLs.
        private def self.precache_file_path(url : String, output_dir : String, base_path : String) : String
          rel = url
          rel = rel[base_path.size..] if !base_path.empty? && rel.starts_with?(base_path)
          rel = rel.lchop('/')
          fpath = File.join(output_dir, rel)
          fpath = File.join(fpath, "index.html") if rel.empty? || rel.ends_with?('/')
          fpath
        end

        # Does the output file backing this precache URL exist on disk?
        private def self.precache_file_exists?(url : String, output_dir : String, base_path : String) : Bool
          File.file?(precache_file_path(url, output_dir, base_path))
        end

        # Resolve an icon's declared `sizes`. Prefer the real pixel dimensions
        # read from the PNG header so a 200x60 logo isn't mislabeled "512x512";
        # fall back to the filename heuristic for non-PNG icons or unparsable
        # bytes.
        private def self.icon_size(icon_path : String, output_dir : String) : String
          # A remote icon (http(s)://) has no local file to read — use the
          # filename heuristic directly instead of warning on every build.
          if File.extname(icon_path).downcase == ".png" && !external_url?(icon_path)
            if dims = png_dimensions(resolve_icon_file(icon_path, output_dir))
              return "#{dims[0]}x#{dims[1]}"
            end
            Logger.warn "PWA: could not read PNG dimensions for icon #{icon_path.inspect}; falling back to filename-derived size #{extract_icon_size(icon_path).inspect}"
          end
          extract_icon_size(icon_path)
        end

        # Map an icon path (config value) to the built output file it lands at.
        # `static/foo.png` and `/foo.png` both copy to `<output>/foo.png`.
        private def self.resolve_icon_file(icon_path : String, output_dir : String) : String
          rel = normalize_icon_path(icon_path).lchop('/')
          File.join(output_dir, rel)
        end

        # Read width/height from a PNG's IHDR chunk. Verifies the 8-byte PNG
        # signature, then reads two big-endian UInt32s at offsets 16 (width)
        # and 20 (height). Returns nil when the file is missing, too short, or
        # not a PNG so the caller can fall back to the filename heuristic.
        PNG_SIGNATURE = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

        private def self.png_dimensions(path : String) : {UInt32, UInt32}?
          return unless File.file?(path)
          header = Bytes.new(24)
          read = File.open(path, &.read(header))
          return if read < 24
          return unless header[0, 8] == PNG_SIGNATURE
          width = IO::ByteFormat::BigEndian.decode(UInt32, header[16, 4])
          height = IO::ByteFormat::BigEndian.decode(UInt32, header[20, 4])
          return if width.zero? || height.zero?
          {width, height}
        rescue ex : IO::Error | File::Error
          Logger.debug "PWA: failed reading PNG header for #{path}: #{ex.message}"
          nil
        end

        # Normalize icon path to a URL path.
        # Strips "static/" prefix since Hwaro copies static/ contents to the output root.
        # Preserves absolute URLs (http:// or https://) as-is.
        private def self.normalize_icon_path(path : String) : String
          return path if path.starts_with?("http://") || path.starts_with?("https://")
          url = path.lchop("static/")
          url.starts_with?("/") ? url : "/#{url}"
        end

        # Extract icon size from filename convention (e.g., icon-192.png → "192x192")
        private def self.extract_icon_size(path : String) : String
          basename = File.basename(path, File.extname(path))
          if match = basename.match(/(\d+)x(\d+)/)
            "#{match[1]}x#{match[2]}"
          elsif match = basename.match(/(\d{2,4})/)
            "#{match[1]}x#{match[1]}"
          else
            "512x512"
          end
        end

        # Determine MIME type from file extension
        private def self.mime_type_for(path : String) : String
          case File.extname(path).downcase
          when ".png"          then "image/png"
          when ".jpg", ".jpeg" then "image/jpeg"
          when ".svg"          then "image/svg+xml"
          when ".webp"         then "image/webp"
          when ".ico"          then "image/x-icon"
          else                      "image/png"
          end
        end
      end
    end
  end
end
