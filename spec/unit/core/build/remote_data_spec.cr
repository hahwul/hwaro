require "../../../spec_helper"

# Specs for `[[data.remote]]` — declarative remote data sources (issue #753):
# config parsing/validation, format inference, env interpolation, cache TTL
# freshness, the three on_error paths, HTTP hygiene (redirects, schemes,
# size cap, credential scoping) and the disk/remote key-collision rule.
#
# Every HTTP interaction runs against an in-process HTTP::Server bound to
# 127.0.0.1:0 — these specs never touch the external network.

# Boot an in-process HTTP server on an ephemeral port and yield its base URL.
private def with_test_server(handler : HTTP::Server::Context ->, & : String ->)
  server = HTTP::Server.new(&handler)
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  # Let the listen fiber start before the block (and the ensure-close) run,
  # or a fast example can close the server before listen was ever called.
  Fiber.yield
  begin
    yield "http://127.0.0.1:#{address.port}"
  ensure
    server.close
  end
end

private def remote_entry(url : String, **opts) : Hwaro::Models::RemoteDataConfig
  entry = Hwaro::Models::RemoteDataConfig.new(opts[:key]? || "team", url)
  entry.format = opts[:format]?
  entry.on_error = opts[:on_error]? || "fail"
  entry.cache_ttl = opts[:cache_ttl]?
  if headers = opts[:headers]?
    entry.headers = headers
  end
  entry
end

private alias RemoteData = Hwaro::Core::Build::RemoteData

# Expose the built site for assertions (same reopen as builder_data_authors_spec).
module Hwaro::Core::Build
  class Builder
    def site
      @site
    end
  end
end

describe "[[data.remote]] config parsing" do
  it "parses a fully specified entry" do
    config = load_config(<<-TOML)
      title = "Test"

      [[data.remote]]
      key = "team"
      url = "https://api.example.com/team"
      format = "json"
      headers = { Authorization = "Bearer literal-token", Accept = "application/json" }
      cache = "1h30m"
      on_error = "warn-and-use-cache"
      TOML

    config.data_remote.size.should eq(1)
    entry = config.data_remote[0]
    entry.key.should eq("team")
    entry.url.should eq("https://api.example.com/team")
    entry.format.should eq("json")
    entry.headers["Authorization"].should eq("Bearer literal-token")
    entry.headers["Accept"].should eq("application/json")
    entry.cache_ttl.should eq(90.minutes)
    entry.on_error.should eq("warn-and-use-cache")
  end

  it "applies defaults: no format, no headers, no cache, on_error fail" do
    config = load_config(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://api.example.com/team"
      TOML

    entry = config.data_remote[0]
    entry.format.should be_nil
    entry.headers.should be_empty
    entry.cache_ttl.should be_nil
    entry.on_error.should eq("fail")
  end

  it "leaves data_remote empty when no [[data.remote]] is configured" do
    load_config(%(title = "Test")).data_remote.should be_empty
  end

  it "does not warn about 'data' as an unknown top-level key" do
    log = with_captured_log do
      load_config(<<-TOML)
        [[data.remote]]
        key = "team"
        url = "https://api.example.com/team"
        TOML
    end
    log.should_not contain("Unknown key 'data'")
  end

  it "normalizes format yml to yaml" do
    config = load_config(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://api.example.com/team"
      format = "yml"
      TOML
    config.data_remote[0].format.should eq("yaml")
  end

  it "accepts single-unit cache durations" do
    {"90s" => 90.seconds, "30m" => 30.minutes, "1h" => 1.hour, "7d" => 7.days}.each do |spec, span|
      config = load_config(<<-TOML)
        [[data.remote]]
        key = "team"
        url = "https://api.example.com/team"
        cache = "#{spec}"
        TOML
      config.data_remote[0].cache_ttl.should eq(span)
    end
  end

  it "rejects a [data.remote] single table instead of silently ignoring it" do
    err = expect_config_error(<<-TOML)
      [data.remote]
      key = "team"
      url = "https://api.example.com/team"
      TOML
    (err.message || "").should contain("[[data.remote]]")
  end

  it "rejects an entry with no key" do
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      url = "https://api.example.com/team"
      TOML
    (err.message || "").should contain("entry 1")
    (err.message || "").should contain("key")
  end

  it "rejects an entry with no url" do
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      key = "team"
      TOML
    (err.message || "").should contain("\"team\"")
    (err.message || "").should contain("url")
  end

  it "rejects a key with characters that cannot name a cache file" do
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      key = "../evil"
      url = "https://api.example.com/team"
      TOML
    (err.message || "").should contain("letters, digits")
  end

  it "rejects duplicate keys across entries" do
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://api.example.com/a"

      [[data.remote]]
      key = "team"
      url = "https://api.example.com/b"
      TOML
    (err.message || "").should contain("Duplicate")
    (err.message || "").should contain("\"team\"")
  end

  it "rejects non-http(s) URL schemes at config load" do
    ["ftp://example.com/x", "file:///etc/passwd", "gopher://example.com", "data:text/plain,hi"].each do |bad|
      err = expect_config_error(<<-TOML)
        [[data.remote]]
        key = "team"
        url = "#{bad}"
        TOML
      (err.message || "").should contain("http")
    end
  end

  it "rejects a relative url" do
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "/just/a/path"
      TOML
    (err.message || "").should contain("http")
  end

  it "rejects an unknown format value" do
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://api.example.com/team"
      format = "xml"
      TOML
    (err.message || "").should contain("xml")
    (err.message || "").should contain("json")
  end

  it "rejects an invalid cache duration" do
    %w[1x fast -5m 1.5h].each do |bad|
      err = expect_config_error(<<-TOML)
        [[data.remote]]
        key = "team"
        url = "https://api.example.com/team"
        cache = "#{bad}"
        TOML
      (err.message || "").should contain("cache duration")
    end
  end

  it "rejects an unknown on_error value" do
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://api.example.com/team"
      on_error = "ignore"
      TOML
    (err.message || "").should contain("ignore")
    (err.message || "").should contain("warn-and-use-cache")
  end

  it "warns about unknown keys inside an entry" do
    log = with_captured_log do
      load_config(<<-TOML)
        [[data.remote]]
        key = "team"
        url = "https://api.example.com/team"
        on_eror = "fail"
        TOML
    end
    log.should contain("on_eror")
  end
end

describe "[[data.remote]] env interpolation" do
  it "substitutes ${VAR} in url and header values" do
    ENV["HWARO_SPEC_REMOTE_TOKEN"] = "tok-123"
    ENV["HWARO_SPEC_REMOTE_HOST"] = "api.example.com"
    begin
      config = load_config(<<-TOML)
        [[data.remote]]
        key = "team"
        url = "https://${HWARO_SPEC_REMOTE_HOST}/team"
        headers = { Authorization = "Bearer ${HWARO_SPEC_REMOTE_TOKEN}" }
        TOML
      entry = config.data_remote[0]
      entry.url.should eq("https://api.example.com/team")
      entry.headers["Authorization"].should eq("Bearer tok-123")
    ensure
      ENV.delete("HWARO_SPEC_REMOTE_TOKEN")
      ENV.delete("HWARO_SPEC_REMOTE_HOST")
    end
  end

  # An unset variable is a hard error, but only for the command that
  # actually fetches. `hwaro deploy`, `hwaro new` and `hwaro tool ...` load
  # the very same config.toml and never touch the network — they used to
  # abort on a remote source they would never read. The error moved to
  # RemoteData.load (see "[[data.remote]] unresolved ${VAR}" below).
  it "loads the config cleanly when a url variable is unset, leaving the placeholder in place" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    config = load_config(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://api.example.com/team?v=${HWARO_SPEC_REMOTE_UNSET}"
      TOML
    config.data_remote[0].url.should eq("https://api.example.com/team?v=${HWARO_SPEC_REMOTE_UNSET}")
  end

  it "loads the config cleanly when a header variable is unset" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    config = load_config(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://api.example.com/team"
      headers = { Authorization = "Bearer ${HWARO_SPEC_REMOTE_UNSET}" }
      TOML
    config.data_remote[0].headers["Authorization"].should eq("Bearer ${HWARO_SPEC_REMOTE_UNSET}")
  end

  it "still validates the rest of the entry's shape when a variable is unset" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://api.example.com/${HWARO_SPEC_REMOTE_UNSET}/team"
      on_error = "explode"
      TOML
    (err.message || "").should contain("on_error")
  end

  it "uses the fallback for ${VAR:-default} without erroring" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    config = load_config(<<-TOML)
      [[data.remote]]
      key = "team"
      url = "https://${HWARO_SPEC_REMOTE_UNSET:-fallback.example.com}/team"
      TOML
    config.data_remote[0].url.should eq("https://fallback.example.com/team")
  end
end

describe "RemoteData.resolve_format" do
  it "prefers the explicit format over everything" do
    RemoteData.resolve_format("toml", "application/json", "https://x.example/a.csv").should eq("toml")
  end

  it "infers from Content-Type, ignoring parameters" do
    RemoteData.resolve_format(nil, "application/json; charset=utf-8", "https://x.example/a").should eq("json")
    RemoteData.resolve_format(nil, "application/vnd.api+json", "https://x.example/a").should eq("json")
    RemoteData.resolve_format(nil, "application/toml", "https://x.example/a").should eq("toml")
    RemoteData.resolve_format(nil, "application/x-yaml", "https://x.example/a").should eq("yaml")
    RemoteData.resolve_format(nil, "text/csv", "https://x.example/a").should eq("csv")
  end

  it "falls back to the URL path extension when Content-Type is unhelpful" do
    RemoteData.resolve_format(nil, "text/plain", "https://x.example/team.json").should eq("json")
    RemoteData.resolve_format(nil, nil, "https://x.example/team.yml").should eq("yaml")
    RemoteData.resolve_format(nil, nil, "https://x.example/team.toml?v=1").should eq("toml")
    RemoteData.resolve_format(nil, nil, "https://x.example/team.csv").should eq("csv")
  end

  it "returns nil when nothing matches" do
    RemoteData.resolve_format(nil, "text/html", "https://x.example/team").should be_nil
    RemoteData.resolve_format(nil, nil, "https://x.example/team").should be_nil
  end
end

describe "RemoteData.parse_body" do
  it "parses each supported format" do
    RemoteData.parse_body(%({"name": "hwaro"}), "json")["name"].as_s.should eq("hwaro")
    RemoteData.parse_body(%(name = "hwaro"), "toml")["name"].as_s.should eq("hwaro")
    RemoteData.parse_body(%(name: hwaro), "yaml")["name"].as_s.should eq("hwaro")

    csv = RemoteData.parse_body("name,role\nalice, dev\n", "csv")
    rows = csv.as_a
    rows.size.should eq(2)
    rows[0].as_a[0].as_s.should eq("name")
    # Cells are stripped, matching the template-facing load_data() shape.
    rows[1].as_a[1].as_s.should eq("dev")
  end

  it "strips a UTF-8 BOM before parsing" do
    RemoteData.parse_body("﻿{\"ok\": true}", "json")["ok"].truthy?.should be_true
  end
end

describe "RemoteData.load" do
  it "fetches, sends configured headers, and parses the payload" do
    seen_auth = nil.as(String?)
    seen_ua = nil.as(String?)
    handler = ->(ctx : HTTP::Server::Context) do
      seen_auth = ctx.request.headers["Authorization"]?
      seen_ua = ctx.request.headers["User-Agent"]?
      ctx.response.content_type = "application/json"
      ctx.response.print %({"name": "hwaro-team"})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team", headers: {"Authorization" => "Bearer tok-123"})
        result = RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
        result.should_not be_nil
        result.not_nil!.value["name"].as_s.should eq("hwaro-team")
      end
    end

    seen_auth.should eq("Bearer tok-123")
    seen_ua.should eq("Hwaro")
  end

  it "makes a freshly created .hwaro/ cache workspace ignore itself" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.content_type = "application/json"
      ctx.response.print %({"ok": true})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        # The default layout: CACHE_DIR = ".hwaro/remote_data".
        cache_dir = File.join(dir, ".hwaro", "remote_data")
        RemoteData.load(remote_entry("#{base}/a"), cache_dir: cache_dir)
        File.read(File.join(dir, ".hwaro", ".gitignore")).should eq("*\n")

        # A custom cache location gets no .gitignore sprinkled next to it.
        custom = File.join(dir, "custom-cache")
        RemoteData.load(remote_entry("#{base}/b"), cache_dir: custom)
        File.exists?(File.join(dir, ".gitignore")).should be_false
      end
    end
  end

  it "skips the request while the disk cache is within the TTL and refetches after it expires" do
    hits = Atomic(Int32).new(0)
    handler = ->(ctx : HTTP::Server::Context) do
      hits.add(1)
      ctx.response.content_type = "application/json"
      ctx.response.print %({"hit": #{hits.get}})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        cache_dir = File.join(dir, "cache")
        t0 = Time.utc
        entry = remote_entry("#{base}/team", cache_ttl: 1.hour)

        first = RemoteData.load(entry, cache_dir: cache_dir, now: t0).not_nil!
        hits.get.should eq(1)

        # Within the TTL: served from disk, no request.
        second = RemoteData.load(entry, cache_dir: cache_dir, now: t0 + 30.minutes).not_nil!
        hits.get.should eq(1)
        second.value["hit"].as_number.should eq(first.value["hit"].as_number)

        # Past the TTL: refetched.
        third = RemoteData.load(entry, cache_dir: cache_dir, now: t0 + 2.hours).not_nil!
        hits.get.should eq(2)
        third.value["hit"].as_number.should eq(2)
      end
    end
  end

  it "refetches on every load when no cache TTL is configured" do
    hits = Atomic(Int32).new(0)
    handler = ->(ctx : HTTP::Server::Context) do
      hits.add(1)
      ctx.response.content_type = "application/json"
      ctx.response.print %({"ok": true})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        cache_dir = File.join(dir, "cache")
        entry = remote_entry("#{base}/team")
        RemoteData.load(entry, cache_dir: cache_dir)
        RemoteData.load(entry, cache_dir: cache_dir)
        hits.get.should eq(2)
      end
    end
  end

  it "does not serve a fresh cache entry for a different url" do
    hits = Atomic(Int32).new(0)
    handler = ->(ctx : HTTP::Server::Context) do
      hits.add(1)
      ctx.response.content_type = "application/json"
      ctx.response.print %({"path": "#{ctx.request.path}"})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        cache_dir = File.join(dir, "cache")
        t0 = Time.utc
        RemoteData.load(remote_entry("#{base}/a", cache_ttl: 1.hour), cache_dir: cache_dir, now: t0)
        hits.get.should eq(1)

        # Same key, new url: the cached copy must not answer.
        result = RemoteData.load(remote_entry("#{base}/b", cache_ttl: 1.hour), cache_dir: cache_dir, now: t0).not_nil!
        hits.get.should eq(2)
        result.value["path"].as_s.should eq("/b")
      end
    end
  end

  it "on_error = fail raises a classified HWARO_E_NETWORK error without leaking the query string" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.status_code = 500
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team.json?token=sekret-value")
        err = expect_raises(Hwaro::HwaroError) do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
        (err.message || "").should contain("site.data.team")
        (err.message || "").should contain("HTTP 500")
        (err.message || "").should_not contain("sekret-value")
      end
    end
  end

  it "on_error = warn-and-use-cache falls back to the cached copy when the source fails" do
    fail_now = Atomic(Int32).new(0)
    handler = ->(ctx : HTTP::Server::Context) do
      if fail_now.get > 0
        ctx.response.status_code = 503
      else
        ctx.response.content_type = "application/json"
        ctx.response.print %({"name": "cached-team"})
      end
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        cache_dir = File.join(dir, "cache")
        entry = remote_entry("#{base}/team", on_error: "warn-and-use-cache")

        # Prime the cache with a successful fetch (no TTL: cache is still written).
        RemoteData.load(entry, cache_dir: cache_dir).not_nil!

        fail_now.set(1)
        log = with_captured_log do
          result = RemoteData.load(entry, cache_dir: cache_dir).not_nil!
          result.value["name"].as_s.should eq("cached-team")
        end
        log.should contain("HTTP 503")
        log.should contain("cached copy")
      end
    end
  end

  it "on_error = warn-and-use-cache raises when no cached copy exists" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.status_code = 503
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team", on_error: "warn-and-use-cache")
        err = expect_raises(Hwaro::HwaroError) do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
        (err.message || "").should contain("no usable cached copy")
      end
    end
  end

  it "on_error = warn-and-skip warns and returns nil" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.status_code = 404
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team", on_error: "warn-and-skip")
        log = with_captured_log do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache")).should be_nil
        end
        log.should contain("HTTP 404")
        log.should contain("missing this build")
      end
    end
  end

  it "follows same-origin redirects, keeping configured headers" do
    seen_auth = nil.as(String?)
    handler = ->(ctx : HTTP::Server::Context) do
      case ctx.request.path
      when "/old"
        ctx.response.status_code = 302
        ctx.response.headers["Location"] = "/new"
      else
        seen_auth = ctx.request.headers["Authorization"]?
        ctx.response.content_type = "application/json"
        ctx.response.print %({"moved": true})
      end
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/old", headers: {"Authorization" => "Bearer tok-123"})
        result = RemoteData.load(entry, cache_dir: File.join(dir, "cache")).not_nil!
        result.value["moved"].truthy?.should be_true
      end
    end

    seen_auth.should eq("Bearer tok-123")
  end

  it "drops configured headers on a cross-origin redirect" do
    seen_auth = "unset".as(String?)
    target_handler = ->(ctx : HTTP::Server::Context) do
      seen_auth = ctx.request.headers["Authorization"]?
      ctx.response.content_type = "application/json"
      ctx.response.print %({"ok": true})
    end

    with_test_server(target_handler) do |target_base|
      redirect_handler = ->(ctx : HTTP::Server::Context) do
        ctx.response.status_code = 302
        ctx.response.headers["Location"] = "#{target_base}/data"
      end

      with_test_server(redirect_handler) do |base|
        Dir.mktmpdir do |dir|
          entry = remote_entry("#{base}/old", headers: {"Authorization" => "Bearer tok-123"})
          result = RemoteData.load(entry, cache_dir: File.join(dir, "cache")).not_nil!
          result.value["ok"].truthy?.should be_true
        end
      end
    end

    seen_auth.should be_nil
  end

  it "rejects a redirect to a non-http(s) scheme" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.status_code = 302
      ctx.response.headers["Location"] = "ftp://evil.example/x"
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team")
        err = expect_raises(Hwaro::HwaroError) do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
        end
        (err.message || "").should contain("http")
      end
    end
  end

  it "gives up after the redirect limit" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.status_code = 302
      ctx.response.headers["Location"] = "/loop"
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/loop")
        err = expect_raises(Hwaro::HwaroError) do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
        end
        (err.message || "").should contain("too many redirects")
      end
    end
  end

  it "enforces the response size cap" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.content_type = "application/json"
      ctx.response.print %({"pad": "#{"x" * 200}"})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/big.json")
        err = expect_raises(Hwaro::HwaroError) do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache"), max_bytes: 64_i64)
        end
        (err.message || "").should contain("size cap")
      end
    end
  end

  it "raises a clear error when the format cannot be inferred" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.content_type = "text/plain"
      ctx.response.print "who knows"
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/mystery")
        err = expect_raises(Hwaro::HwaroError) do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
        end
        (err.message || "").should contain("cannot infer")
        (err.message || "").should contain("format")
      end
    end
  end

  it "treats an unparsable payload as a failure, honoring on_error" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.content_type = "application/json"
      ctx.response.print "{not json"
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/broken", on_error: "warn-and-skip")
        log = with_captured_log do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache")).should be_nil
        end
        log.should contain("skipping")
      end
    end
  end
end

describe "builder integration for [[data.remote]]" do
  it "fetches each key once per build and exposes it as site.data" do
    hits = Atomic(Int32).new(0)
    handler = ->(ctx : HTTP::Server::Context) do
      hits.add(1)
      ctx.response.content_type = "application/json"
      ctx.response.print %({"name": "hwaro-team", "size": 3})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", <<-TOML)
            title = "Test"

            [[data.remote]]
            key = "team"
            url = "#{base}/team.json"
            TOML

          FileUtils.mkdir_p("content")
          File.write("content/a.md", "---\ntitle: A\ndate: 2023-01-01\n---\nA\n")
          File.write("content/b.md", "---\ntitle: B\ndate: 2023-01-02\n---\nB\n")

          builder = Hwaro::Core::Build::Builder.new
          builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public"))

          site = builder.site.not_nil!
          site.data["team"]["name"].as_s.should eq("hwaro-team")
          hits.get.should eq(1)

          # The disk cache landed outside every watched directory.
          File.exists?(".hwaro/remote_data/team.data").should be_true
          Dir.exists?("data").should be_false
        end
      end
    end
  end

  it "raises a config error naming both sources when a remote key collides with a data/ file" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.content_type = "application/json"
      ctx.response.print %({"never": "fetched"})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", <<-TOML)
            title = "Test"

            [[data.remote]]
            key = "team"
            url = "#{base}/team.json"
            TOML

          FileUtils.mkdir_p("data")
          File.write("data/team.json", %({"local": true}))
          FileUtils.mkdir_p("content")
          File.write("content/a.md", "---\ntitle: A\ndate: 2023-01-01\n---\nA\n")

          builder = Hwaro::Core::Build::Builder.new
          err = expect_raises(Hwaro::HwaroError) do
            builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public"))
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
          (err.message || "").should contain("data/team.json")
          (err.message || "").should contain("[[data.remote]]")
        end
      end
    end
  end
end

# --- Post-merge review follow-ups (PR #759) ------------------------------
#
# Every example below is a regression guard for one verified finding: they
# all failed (or crashed) against the merged implementation.

describe "RemoteData compressed-body failures" do
  # HTTP::Client sends `Accept-Encoding: gzip, deflate` by default, so a
  # source answering `Content-Encoding: gzip` with bytes that are not gzip
  # raises Compress::Gzip::Error out of the body read — a fetch failure like
  # any other, which must flow through `on_error` instead of escaping
  # unclassified and killing the build.
  corrupt_gzip = ->(ctx : HTTP::Server::Context) do
    ctx.response.headers["Content-Encoding"] = "gzip"
    ctx.response.content_type = "application/json"
    ctx.response.print "this is definitely not a gzip stream"
  end

  it "on_error = warn-and-skip warns and returns nil for a corrupt gzip body" do
    with_test_server(corrupt_gzip) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team.json", on_error: "warn-and-skip")
        log = with_captured_log do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache")).should be_nil
        end
        log.should contain("missing this build")
      end
    end
  end

  it "on_error = fail raises a classified HWARO_E_NETWORK error for a corrupt gzip body" do
    with_test_server(corrupt_gzip) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team.json")
        err = expect_raises(Hwaro::HwaroError) do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
        (err.message || "").should contain("site.data.team")
      end
    end
  end

  it "classifies a corrupt deflate body the same way" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.headers["Content-Encoding"] = "deflate"
      ctx.response.content_type = "application/json"
      ctx.response.print "this is definitely not a deflate stream"
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team.json", on_error: "warn-and-skip")
        log = with_captured_log do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache")).should be_nil
        end
        log.should contain("missing this build")
      end
    end
  end
end

describe "RemoteData fetch deadline" do
  it "gives up on a slow-drip source at the overall fetch deadline" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.content_type = "application/json"
      # Content-Length keeps the client reading until the deadline fires;
      # each drip lands well inside READ_TIMEOUT, which is why a per-read
      # timeout alone never trips here.
      ctx.response.headers["Content-Length"] = "200"
      200.times do
        ctx.response.print "x"
        ctx.response.flush
        sleep 100.milliseconds
      end
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/slow.json")
        started = Time.instant
        err = expect_raises(Hwaro::HwaroError) do
          RemoteData.load(entry, cache_dir: File.join(dir, "cache"), deadline: 1.second)
        end
        elapsed = Time.instant - started
        (err.message || "").should contain("fetch deadline")
        # 20s of drip, abandoned after ~1s.
        elapsed.should be < 10.seconds
      end
    end
  end

  it "leaves a prompt response untouched" do
    handler = ->(ctx : HTTP::Server::Context) do
      ctx.response.content_type = "application/json"
      ctx.response.print %({"ok": true})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team.json")
        result = RemoteData.load(entry, cache_dir: File.join(dir, "cache"), deadline: 30.seconds).not_nil!
        result.value["ok"].truthy?.should be_true
      end
    end
  end
end

describe "RemoteData format inference after a redirect" do
  it "infers the format from the URL the redirect actually landed on" do
    handler = ->(ctx : HTTP::Server::Context) do
      if ctx.request.path == "/team"
        ctx.response.status_code = 302
        ctx.response.headers["Location"] = "/cdn/team.json"
      else
        # A CDN that serves everything as octet-stream: the response says
        # nothing, so only the post-redirect extension can answer.
        ctx.response.content_type = "application/octet-stream"
        ctx.response.print %({"name": "redirected-team"})
      end
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team")
        result = RemoteData.load(entry, cache_dir: File.join(dir, "cache")).not_nil!
        result.value["name"].as_s.should eq("redirected-team")
      end
    end
  end

  it "still lets an explicit format win over the post-redirect extension" do
    handler = ->(ctx : HTTP::Server::Context) do
      if ctx.request.path == "/team"
        ctx.response.status_code = 302
        ctx.response.headers["Location"] = "/cdn/team.json"
      else
        ctx.response.content_type = "application/octet-stream"
        ctx.response.print %(name = "toml-team")
      end
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        entry = remote_entry("#{base}/team", format: "toml")
        result = RemoteData.load(entry, cache_dir: File.join(dir, "cache")).not_nil!
        result.value["name"].as_s.should eq("toml-team")
      end
    end
  end
end

describe "[[data.remote]] unresolved ${VAR}" do
  it "raises a classified HWARO_E_CONFIG naming the variable when the entry is used" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    Dir.mktmpdir do |dir|
      entry = remote_entry("https://api.example.com/team?v=${HWARO_SPEC_REMOTE_UNSET}")
      err = expect_raises(Hwaro::HwaroError) do
        RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("HWARO_SPEC_REMOTE_UNSET")
      (err.message || "").should contain("not set")
    end
  end

  it "names the header but never echoes its value" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    Dir.mktmpdir do |dir|
      entry = remote_entry("https://api.example.com/team",
        headers: {"Authorization" => "Bearer ${HWARO_SPEC_REMOTE_UNSET}"})
      err = expect_raises(Hwaro::HwaroError) do
        RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("HWARO_SPEC_REMOTE_UNSET")
      (err.message || "").should contain("Authorization")
      (err.message || "").should_not contain("Bearer")
    end
  end

  # on_error softens flaky SOURCES, never a config mistake: silently
  # skipping the key would leave site.data.<key> undefined and blame the
  # template that dereferences it.
  it "is not softened by on_error" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    Dir.mktmpdir do |dir|
      entry = remote_entry("https://api.example.com/team?v=${HWARO_SPEC_REMOTE_UNSET}", on_error: "warn-and-skip")
      err = expect_raises(Hwaro::HwaroError) do
        RemoteData.load(entry, cache_dir: File.join(dir, "cache"))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end
  end

  it "fails the build with that error, naming the variable" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML)
          title = "Test"

          [[data.remote]]
          key = "team"
          url = "https://api.example.com/team?v=${HWARO_SPEC_REMOTE_UNSET}"
          TOML
        FileUtils.mkdir_p("content")
        File.write("content/a.md", "---\ntitle: A\ndate: 2023-01-01\n---\nA\n")

        builder = Hwaro::Core::Build::Builder.new
        err = expect_raises(Hwaro::HwaroError) do
          builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public"))
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain("HWARO_SPEC_REMOTE_UNSET")
      end
    end
  end

  it "lets a command that only reads the config run to completion" do
    ENV.delete("HWARO_SPEC_REMOTE_UNSET")
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML)
          title = "Test"
          base_url = "https://example.com"

          [[data.remote]]
          key = "team"
          url = "https://api.example.com/team"
          headers = { Authorization = "Bearer ${HWARO_SPEC_REMOTE_UNSET}" }

          [deployment]
          source_dir = "public"
          TOML

        # `hwaro deploy` / `hwaro new` / `hwaro tool ...` all reach the site
        # through Config.load and never fetch: this must not raise.
        config = Hwaro::Models::Config.load
        config.title.should eq("Test")
        config.deployment.source_dir.should eq("public")
        config.data_remote[0].headers["Authorization"].should contain("${HWARO_SPEC_REMOTE_UNSET}")
      end
    end
  end
end

describe "[[data.remote]] case-colliding keys" do
  # "Team" and "team" are two entries in config.toml but ONE pair of files
  # under .hwaro/remote_data/ on macOS/Windows, so they overwrite each
  # other's payload and meta every build.
  it "rejects keys that differ only in case" do
    err = expect_config_error(<<-TOML)
      [[data.remote]]
      key = "Team"
      url = "https://api.example.com/team"

      [[data.remote]]
      key = "team"
      url = "https://api.example.com/other"
      TOML
    (err.message || "").should contain("Duplicate")
    (err.message || "").should contain("case-insensitive")
  end

  it "still accepts keys that differ by more than case" do
    config = load_config(<<-TOML)
      [[data.remote]]
      key = "Team"
      url = "https://api.example.com/team"

      [[data.remote]]
      key = "team_us"
      url = "https://api.example.com/other"
      TOML
    config.data_remote.map(&.key).should eq(["Team", "team_us"])
  end
end

describe "[[data.remote]] serve-session memo" do
  private_config = ->(base : String, cache : String) do
    <<-TOML
      title = "Test"

      [[data.remote]]
      key = "team"
      url = "#{base}/team.json"
      #{cache}
      TOML
  end

  it "fetches once per serve session and keeps rebuilding when the source goes away" do
    hits = Atomic(Int32).new(0)
    server = HTTP::Server.new do |ctx|
      hits.add(1)
      ctx.response.content_type = "application/json"
      ctx.response.print %({"name": "hwaro-team"})
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    Fiber.yield
    base = "http://127.0.0.1:#{address.port}"

    begin
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", private_config.call(base, ""))
          FileUtils.mkdir_p("content")
          File.write("content/a.md", "---\ntitle: A\ndate: 2023-01-01\n---\nA\n")

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", serve_mode: true)

          builder.run(options)
          builder.site.not_nil!.data["team"]["name"].as_s.should eq("hwaro-team")
          hits.get.should eq(1)

          # The source is gone; a serve rebuild must still succeed, and the
          # no-TTL entry must not even try to refetch.
          server.close
          builder.run(options)
          builder.site.not_nil!.data["team"]["name"].as_s.should eq("hwaro-team")
          hits.get.should eq(1)
        end
      end
    ensure
      server.close rescue nil
    end
  end

  it "warns and reuses the session payload when a TTL-expired refetch fails" do
    healthy = Atomic(Int32).new(1)
    server = HTTP::Server.new do |ctx|
      if healthy.get > 0
        ctx.response.content_type = "application/json"
        ctx.response.print %({"name": "hwaro-team"})
      else
        ctx.response.status_code = 503
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    Fiber.yield
    base = "http://127.0.0.1:#{address.port}"

    begin
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          # on_error defaults to "fail", and the disk cache is never consulted
          # in that mode — the memo is the only thing that can save this build.
          File.write("config.toml", private_config.call(base, %(cache = "1s")))
          FileUtils.mkdir_p("content")
          File.write("content/a.md", "---\ntitle: A\ndate: 2023-01-01\n---\nA\n")

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", serve_mode: true)
          builder.run(options)
          builder.site.not_nil!.data["team"]["name"].as_s.should eq("hwaro-team")

          healthy.set(0)
          sleep 1200.milliseconds
          log = with_captured_log { builder.run(options) }
          builder.site.not_nil!.data["team"]["name"].as_s.should eq("hwaro-team")
          log.should contain("HTTP 503")
          log.should contain("serve session")
        end
      end
    ensure
      server.close rescue nil
    end
  end

  it "does not memoize for a plain build" do
    hits = Atomic(Int32).new(0)
    handler = ->(ctx : HTTP::Server::Context) do
      hits.add(1)
      ctx.response.content_type = "application/json"
      ctx.response.print %({"name": "hwaro-team"})
    end

    with_test_server(handler) do |base|
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", private_config.call(base, ""))
          FileUtils.mkdir_p("content")
          File.write("content/a.md", "---\ntitle: A\ndate: 2023-01-01\n---\nA\n")

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public")
          builder.run(options)
          builder.run(options)
          hits.get.should eq(2)
        end
      end
    end
  end
end
