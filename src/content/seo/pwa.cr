require "json"
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
            size = extract_icon_size(icon_path)
            url_path = normalize_icon_path(icon_path)
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
              json.field "start_url", pwa.start_url
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
          File.write(path, manifest)
          Logger.action :create, path if verbose
          Logger.info "  Generated manifest.json"
        end

        private def self.generate_service_worker(site : Models::Site, output_dir : String, verbose : Bool)
          config = site.config
          pwa = config.pwa

          # Build precache URL list
          precache_urls = pwa.precache_urls.dup
          precache_urls << pwa.start_url unless precache_urls.includes?(pwa.start_url)
          if offline = pwa.offline_page
            precache_urls << offline unless precache_urls.includes?(offline)
          end

          precache_json = precache_urls.map(&.inspect).join(",\n  ")
          offline_url = if op = pwa.offline_page
                          op.inspect
                        else
                          pwa.start_url.inspect
                        end
          cache_version = Time.utc.to_unix

          fetch_handler = case pwa.cache_strategy
                          when "network-first"
                            network_first_handler(offline_url)
                          when "stale-while-revalidate"
                            stale_while_revalidate_handler(offline_url)
                          else
                            cache_first_handler(offline_url)
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
          File.write(path, sw_content)
          Logger.action :create, path if verbose
          Logger.info "  Generated sw.js"
        end

        # --- Fetch handler strategies ---

        private def self.cache_first_handler(offline_url : String) : String
          <<-JS
          self.addEventListener('fetch', event => {
            if (event.request.mode === 'navigate') {
              event.respondWith(
                fetch(event.request).catch(() =>
                  caches.match(#{offline_url}) || caches.match('/')
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

        private def self.network_first_handler(offline_url : String) : String
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
                    ? caches.match(#{offline_url}) || caches.match('/')
                    : undefined)
                )
              )
            );
          });
          JS
        end

        private def self.stale_while_revalidate_handler(offline_url : String) : String
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
                    return caches.match(#{offline_url}) || caches.match('/');
                  }
                  return undefined;
                });
                return cached || fetchPromise;
              })
            );
          });
          JS
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
