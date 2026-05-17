require "./support/build_helper"
require "http/client"

# Process-level smoke test for `hwaro serve --fast-start`.
#
# Guards against the accept-loop starvation regression: under
# `--fast-start` the deferred-render fiber does ~seconds of pure-CPU
# work (PNG OG image encoding, image resize) right after the server
# starts. If the deferred fiber runs before `server.listen` enters its
# accept loop — or if a CPU-bound hook never yields — TCP connects
# succeed via the OS backlog but HTTP responses never come back.
#
# This test spawns the real built binary so it exercises the actual
# scheduler-level interaction. It's intentionally a single coarse
# assertion: the server must produce an HTTP 200 within a couple of
# seconds of emitting the ready signal.
#
# Skips when `bin/hwaro` isn't present (e.g. running `crystal spec`
# without a prior `shards build`). In CI, the build step runs first
# so the binary is always available.
private HWARO_BIN = File.expand_path("../../bin/hwaro", __DIR__)

private def fast_start_serve_available? : Bool
  return false unless File.exists?(HWARO_BIN)
  File::Info.executable?(HWARO_BIN)
end

private def pick_free_port : Int32
  # Open ephemeral, read the assigned port, close. Race against another
  # process grabbing it before `hwaro serve` binds is theoretically
  # possible but vanishingly small for a unit-spec timeframe.
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

private def wait_for_ready(stdout : IO, deadline : Time)
  loop do
    raise "timed out waiting for hwaro serve ready signal" if Time.utc > deadline
    line = stdout.gets(chomp: true)
    return if line && line.includes?("hwaro serve: ready url=")
  end
end

# Build a site with enough pages that `--fast-start` actually defers
# rendering. The default `fast_start_count` is 20 — we generate 40 so
# at least 20 pages land in the deferred bucket and the BeforeRender
# hooks have non-trivial work to do on the deferred pass.
private def make_fast_start_site(dir : String)
  File.write(File.join(dir, "config.toml"), <<-TOML)
    title = "FS Test"
    base_url = "http://127.0.0.1"

    [og.auto_image]
    enabled = true
    format = "svg"
    TOML

  FileUtils.mkdir_p(File.join(dir, "content"))
  FileUtils.mkdir_p(File.join(dir, "templates"))

  File.write(File.join(dir, "content", "_index.md"), "---\ntitle: Home\n---\nhome")

  (1..40).each do |i|
    File.write(
      File.join(dir, "content", "post-#{i}.md"),
      "---\ntitle: Post #{i}\ndate: 2025-01-#{(i % 28) + 1}\n---\nbody #{i}"
    )
  end

  File.write(File.join(dir, "templates", "page.html"), "<html><body>{{ page.title }}</body></html>")
  File.write(File.join(dir, "templates", "index.html"), "<html><body>{{ page.title }}</body></html>")
end

describe "hwaro serve --fast-start" do
  it "answers HTTP requests immediately after emitting the ready signal" do
    pending! "bin/hwaro not built — run `shards build -Dpreview_mt` first" unless fast_start_serve_available?

    Dir.mktmpdir do |dir|
      make_fast_start_site(dir)

      port = pick_free_port

      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe

      process = Process.new(
        HWARO_BIN,
        args: ["serve", "--fast-start", "--port", port.to_s, "--no-live-reload"],
        chdir: dir,
        input: Process::Redirect::Close,
        output: stdout_w,
        error: stderr_w,
      )

      begin
        # The ready signal must arrive within a few seconds for a
        # 40-page site even on a slow CI runner. Generous deadline to
        # avoid flakes; the real assertion is what happens after.
        wait_for_ready(stdout_r, Time.utc + 30.seconds)

        # Race the request against the deferred pass. Without the
        # accept-loop-starvation fix this would block until the
        # deferred render completes (or timeout).
        client = HTTP::Client.new("127.0.0.1", port)
        client.read_timeout = 5.seconds
        client.connect_timeout = 2.seconds
        response = client.get("/")
        client.close
        response.status_code.should eq(200)
      ensure
        process.terminate(graceful: true) rescue nil
        # Don't leave a zombie if terminate didn't take.
        spawn { process.wait rescue nil }
        stdout_w.close rescue nil
        stderr_w.close rescue nil
        stdout_r.close rescue nil
        stderr_r.close rescue nil
      end
    end
  end
end
