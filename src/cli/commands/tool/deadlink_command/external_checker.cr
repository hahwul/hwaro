# check-links — concurrent HTTP checks with SSRF-safe host resolution.
#
# Reopens `Tool::DeadlinkCommand`; deadlink_command.cr keeps the flag
# metadata, the ivars and `run`. Parts only reopen the class: no requires, no
# load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module CLI
    module Commands
      module Tool
        class DeadlinkCommand
          # Identical external URLs are checked ONCE and the outcome fanned
          # back out to every occurrence — 50 pages linking the same site used
          # to fire 50 simultaneous requests and collect 429 false positives.
          # The worker/channel accounting stays exact: one outcome per unique
          # URL from the pool, then one reported Result per occurrence (each
          # with its own file), in the caller's link order.
          private def check_links_concurrently(links : Array(Link), timeout_seconds : Int32, max_concurrency : Int32) : Array(Result)
            unique_urls = [] of String
            seen = Set(String).new
            links.each do |link|
              unique_urls << link.url if seen.add?(link.url)
            end

            outcomes = check_urls_concurrently(unique_urls, timeout_seconds, max_concurrency)

            links.map do |link|
              status, error_message = outcomes[link.url]
              Result.new(link: link, status: status, error: error_message)
            end
          end

          private def check_urls_concurrently(urls : Array(String), timeout_seconds : Int32, max_concurrency : Int32) : Hash(String, {Int32, String?})
            results_channel = Channel({String, Int32, String?}).new(urls.size)
            work_channel = Channel(String?).new(max_concurrency)

            # Spawn bounded worker pool.
            #
            # Exactly one result per dequeued URL — the same send-guarantee the
            # build's pools carry (see Core::Build::Parallel#process_parallel).
            # A raise here does not kill the process (Crystal's `Fiber#run`
            # prints `Unhandled exception in spawn` and carries on); it kills
            # this WORKER, which is worse: the collector below blocks on
            # `urls.size` receives with no timeout, so one lost result hangs
            # `hwaro tool check-links` forever. `check_external_url` rescues
            # its own network errors today — this makes surviving a raise a
            # property of the pool rather than of one callee.
            max_concurrency.times do
              spawn do
                while url = work_channel.receive?
                  status, error_message = begin
                    check_external_url(url, timeout_seconds)
                  rescue ex
                    # Pure construction — nothing here can raise — so the send
                    # below always runs, exactly once per dequeued URL.
                    {-1, ex.message || ex.class.name}
                  end
                  results_channel.send({url, status, error_message})
                end
              end
            end

            # Feed URLs to workers
            urls.each { |url| work_channel.send(url) }
            max_concurrency.times { work_channel.send(nil) }

            # Collect all results
            outcomes = {} of String => {Int32, String?}
            urls.size.times do
              url, status, error_message = results_channel.receive
              outcomes[url] = {status, error_message}
            end
            outcomes
          end

          # Check one external URL, following redirects. Returns
          # {status, error}. Redirect FAILURES (loop, missing Location,
          # exhausted time budget) report the -1 sentinel, never the redirect
          # code itself, so `--allow-status 301` only matches links whose
          # TERMINAL response is 301 — a broken redirect used to be classified
          # healthy by it.
          private def check_external_url(url : String, timeout_seconds : Int32) : {Int32, String?}
            error_message : String? = nil
            status = begin
              current_uri = URI.parse(url)
              method = "HEAD"
              redirects_left = 5
              response_status = -1
              # Total time budget for the whole redirect chain: each hop can
              # take up to the per-request timeout (HEAD may retry as GET),
              # so without this a slow chain multiplied the configured
              # --timeout by up to 12×. 3× leaves room for a slow-but-healthy
              # chain of a few hops while still bounding the worst case.
              # Int64 math: an absurd-but-accepted --timeout must not
              # overflow Int32 here and flip every link to "dead".
              deadline = Time.instant + (timeout_seconds.to_i64 * 3).seconds

              loop do
                host = current_uri.host
                # Non-ASCII (IDN) hosts are punycoded for DNS/connection;
                # the original URL is kept for reporting.
                connect_host = host ? ascii_host(host) : nil
                if connect_host && private_host?(connect_host)
                  error_message = "Skipped: private/internal address"
                  response_status = -1
                  break
                end

                request_uri = current_uri
                if host && connect_host && connect_host != host
                  request_uri = current_uri.dup
                  request_uri.host = connect_host
                end

                client = HTTP::Client.new(request_uri)
                client.connect_timeout = timeout_seconds.seconds
                client.read_timeout = timeout_seconds.seconds

                begin
                  headers = HTTP::Headers{"User-Agent" => "hwaro-link-checker/1.0"}
                  response = if method == "HEAD"
                               client.head(request_uri.request_target, headers: headers)
                             else
                               client.get(request_uri.request_target, headers: headers)
                             end

                  status_code = response.status_code

                  if {301, 302, 303, 307, 308}.includes?(status_code)
                    if redirects_left > 0
                      location = response.headers["Location"]?
                      if location
                        if Time.instant > deadline
                          error_message = "Request timed out (#{timeout_seconds}s): redirect chain exceeded the time budget"
                          response_status = -1
                          break
                        end
                        current_uri = current_uri.resolve(location)
                        # RFC 9110: 303 See Other is followed with GET.
                        method = "GET" if status_code == 303
                        redirects_left -= 1
                        next
                      else
                        error_message = "Redirect without Location header (#{status_code})"
                        response_status = -1
                        break
                      end
                    else
                      error_message = "Too many redirects (last status #{status_code})"
                      response_status = -1
                      break
                    end
                  elsif method == "HEAD" && {405, 403, 501}.includes?(status_code)
                    method = "GET"
                    next
                  else
                    response_status = status_code
                    break
                  end
                ensure
                  client.close
                end
              end

              response_status
            rescue ex : Socket::ConnectError
              error_message = "Connection failed: #{ex.message}"
              -1
            rescue IO::TimeoutError
              error_message = "Request timed out (#{timeout_seconds}s)"
              -1
            rescue ex : Socket::Addrinfo::Error
              error_message = "DNS resolution failed: #{ex.message}"
              -1
            rescue ex
              error_message = ex.message
              -1
            end
            {status, error_message}
          end

          # RFC 3490 conversion for a host with non-ASCII labels
          # (`例え.jp` → `xn--r8jz45g.jp`) so DNS resolution and the
          # connection use the registrable form — such links used to fail
          # DNS and be reported dead.
          private def ascii_host(host : String) : String
            return host if host.ascii_only?
            URI::Punycode.to_ascii(host)
          rescue ArgumentError
            host
          end

          # Check if a hostname resolves to a private/internal IP address (SSRF protection).
          private def private_host?(host : String) : Bool
            @private_host_cache_mutex.synchronize do
              if @private_host_cache.has_key?(host)
                return @private_host_cache[host]
              end
            end
            result = resolve_private_host?(host)
            @private_host_cache_mutex.synchronize { @private_host_cache[host] = result }
            result
          end

          private def resolve_private_host?(host : String) : Bool
            return true if host == "localhost" || host.ends_with?(".local") || host.ends_with?(".internal")

            begin
              addrs = Socket::Addrinfo.resolve(host, 80, type: Socket::Type::STREAM)
              addrs.any? { |addr| private_ip_address?(addr.ip_address) }
            rescue Socket::Error
              false
            end
          end

          # Structured classification via Socket::IPAddress predicates — the
          # old string-prefix checks missed IPv4-mapped IPv6 loopback
          # (`::ffff:127.0.0.1`) and the fe81–febf link-local range. An
          # IPv4-mapped address is unmapped first because the stdlib
          # predicates only classify the mapped form as loopback, not as
          # private/link-local.
          private def private_ip_address?(ip : Socket::IPAddress) : Bool
            if mapped = ipv4_mapped_address(ip)
              return private_ip_address?(mapped)
            end
            ip.loopback? || ip.private? || ip.link_local? || ip.unspecified?
          end

          private def ipv4_mapped_address(ip : Socket::IPAddress) : Socket::IPAddress?
            return unless ip.family.inet6?
            address = ip.address
            return unless address.starts_with?("::ffff:") && address.includes?('.')
            Socket::IPAddress.new(address.lchop("::ffff:"), 0)
          rescue Socket::Error | ArgumentError
            nil
          end
        end
      end
    end
  end
end
