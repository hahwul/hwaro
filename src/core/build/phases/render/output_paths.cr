# Render phase — output paths, URL-collision arbitration, aliases and redirects.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  # A URL's relative output path, or nil when the URL cannot be published
  # safely. The refuse-outright half of `PathUtils.split_safe_segments` (see
  # there for why dropping a segment is not an option for a writer: it
  # relocates the page onto whatever already occupies the shortened path).
  private def url_output_path(url_path : String) : String?
    segments, refused = Utils::PathUtils.split_safe_segments(url_path)
    return if refused
    segments.join("/")
  end

  # Record that a page the render loop counted could not be published by any
  # sink, so `pages_rendered` can be corrected before it reaches the receipt.
  protected def note_unpublished_page
    @unpublished_pages.add(1)
  end

  # Record that a page actually wrote its output file.
  protected def note_published_page
    @published_pages.add(1)
  end

  # Absolute output path for `page`, or nil when its URL cannot be published
  # safely — either a segment would traverse (see `url_output_path`) or the
  # result lands outside `output_dir`. It must stay nil rather than fall back
  # to `output_dir/<filename>`: that fallback dropped EVERY rejected page onto
  # the site root `index.html`, so the homepage ended up holding whichever
  # page rendered last instead of the page being skipped.
  private def get_output_path(page : Models::Page, output_dir : String, filename : String = "index.html") : String?
    url_path = url_output_path(page.url.lchop("/"))
    return unless url_path
    output_path = File.join(output_dir, url_path, filename)
    Utils::OutputGuard.safe_output_path(output_path, output_dir)
  end

  # Source + output path pair the cache keys a page by. The output path is
  # nil for a page whose URL escapes the output directory (see above).
  private def cache_paths_for(page : Models::Page, output_dir : String) : {String, String?}
    {File.join("content", page.path), get_output_path(page, output_dir)}
  end

  # Claim a deterministic owner (page.path) for every output URL. Two passes,
  # both in source-path order so a collision resolves identically on every
  # build: real page URLs claim first — a page's own content always beats a
  # redirect stub, whatever the path order — then aliases claim what's left.
  # Pages with render=false never write output and therefore claim nothing.
  #
  # Recomputed by the full build and by the incremental/rerender paths, so a
  # collision resolved (or introduced) during a serve session doesn't leave
  # a stale winner suppressing writes until restart.
  private def compute_output_url_winners(all_pages : Array(Models::Page)) : Hash(String, String)
    winners = Hash(String, String).new

    # Second index, keyed by the output FILE rather than the URL string. Two
    # different URLs can name one file — `/foo/` and `/foo//`, or a pair whose
    # difference decodes away — and keying only on the string let the second
    # page overwrite the first with no warning and an exit code of 0.
    by_file = Hash(String, String).new

    # Third index, case- and NFC-folded, because `/Foo/` and `/foo/` ARE the
    # same file on macOS and Windows. The WARNING fires everywhere (a
    # case-sensitive Linux CI must still tell the author their site loses a
    # page on a contributor's Mac), but the write is only suppressed where the
    # filesystem actually folds — suppressing on a case-sensitive host would
    # stop publishing a page that legitimately has both spellings there.
    by_fold = Hash(String, String).new
    folds_case : Bool? = nil

    # Authored pages claim before `[[content.generate]]` pages: when a
    # generated slug lands on an authored URL, the authored page must own
    # the file deterministically — never "whichever path sorts first".
    # Sites without generated pages sort identically to the plain
    # path sort this replaces (every key is {0, path}).
    writers = all_pages.select(&.render).sort_by! { |p| {p.synthesized? ? 1 : 0, p.path} }

    # Cleared before every pass, not just set: this runs again on incremental
    # and serve rerenders, so a collision the author has since resolved must
    # stop suppressing the page (and its sitemap/feed/search entries).
    all_pages.each(&.output_suppressed=(false))

    writers.each do |page|
      url = page.url
      if prev_path = winners[url]?
        Logger.warn "Duplicate output path '#{url}' — '#{page.path}' collides with '#{prev_path}' and is not written"
        page.output_suppressed = true
        next
      end

      # nil = this URL is unpublishable (a segment traverses or hides a
      # separator); write_output refuses it by itself and it claims nothing.
      # It still has to be marked suppressed: the discovery surfaces
      # (sitemap, feeds, search index, llms.txt) and the auto-OG generator
      # only consult `output_suppressed`, so without this the build warned
      # "Not publishing", wrote no file, and then advertised the URL in
      # sitemap.xml and search.json anyway — and rendered an OG image for it.
      file_key = Utils::PathUtils.output_file_key(url)
      page.output_suppressed = true if file_key.nil?
      if file_key
        if prev_path = by_file[file_key]?
          Logger.warn "Duplicate output path '#{url}' — '#{page.path}' collides with '#{prev_path}' and is not written"
          # Point the loser's own URL key at the winner: every sink asks
          # `collision_suppressed?(page, page.url)`, so this is what makes the
          # warning true instead of merely informative.
          winners[url] = prev_path
          page.output_suppressed = true
          next
        end

        fold_key = Utils::PathUtils.output_fold_key(file_key)
        if prev_path = by_fold[fold_key]?
          Logger.warn "Duplicate output path '#{url}' — '#{page.path}' differs from '#{prev_path}' only in letter case or Unicode form, which name the same file on macOS and Windows"
          # Probed lazily: a collision like this is rare, and the probe costs
          # two stat calls. `Dir.current` stands in for the output directory,
          # which hwaro always writes inside the project it was invoked on.
          folds_case = Utils::PathUtils.case_folding_fs?(Dir.current) if folds_case.nil?
          if folds_case
            winners[url] = prev_path
            page.output_suppressed = true
            next
          end
        else
          by_fold[fold_key] = page.path
        end

        by_file[file_key] = page.path
      end

      winners[url] = page.path
    end

    writers.each do |page|
      page.aliases.each do |a|
        norm = normalize_alias_url(a)
        if prev_path = winners[norm]?
          # An alias duplicating its OWN page's URL is silently ignored at
          # write time (generate_aliases); only cross-page collisions warn.
          unless prev_path == page.path
            Logger.warn "Duplicate alias output path '#{norm}' — alias on '#{page.path}' collides with '#{prev_path}' and is not written"
          end
          next
        end

        # A redirect stub is a published file too, so it goes through the same
        # file/fold identity check a page URL does.
        if file_key = Utils::PathUtils.output_file_key(norm)
          if (prev_path = by_file[file_key]?) && prev_path != page.path
            Logger.warn "Duplicate alias output path '#{norm}' — alias on '#{page.path}' collides with '#{prev_path}' and is not written"
            winners[norm] = prev_path
            next
          end

          fold_key = Utils::PathUtils.output_fold_key(file_key)
          if (prev_path = by_fold[fold_key]?) && prev_path != page.path
            Logger.warn "Duplicate alias output path '#{norm}' — alias on '#{page.path}' differs from '#{prev_path}' only in letter case or Unicode form, which name the same file on macOS and Windows"
            folds_case = Utils::PathUtils.case_folding_fs?(Dir.current) if folds_case.nil?
            if folds_case
              winners[norm] = prev_path
              next
            end
          else
            by_fold[fold_key] = page.path
          end

          by_file[file_key] = page.path
        end

        winners[norm] = page.path
      end
    end

    winners
  end

  # Shared by collision detection and alias writing so the suppression keys
  # can never drift from the written paths.
  # Collision key for an alias target.
  #
  # `/foo/`, `/foo/index.html` and `/foo/index.htm` all name the same file on
  # disk, so they must collapse to ONE key or `collision_suppressed?` cannot
  # see the conflict. `aliases = ["/index.html"]` kept its own key, never
  # collided with the homepage's `/`, and its redirect stub was written
  # straight over `public/index.html` — silently, and order-dependently under
  # the parallel render.
  private def normalize_alias_url(alias_path : String) : String
    norm = alias_path.starts_with?("/") ? alias_path : "/#{alias_path}"
    {"index.html", "index.htm"}.each do |leaf|
      if norm == "/#{leaf}"
        return "/"
      elsif norm.ends_with?("/#{leaf}")
        return norm[0, norm.size - leaf.size]
      end
    end
    return norm if norm.ends_with?("/") || norm.ends_with?(".html") || norm.ends_with?(".htm")
    "#{norm}/"
  end

  # True when this page is not the deterministic owner of `url_key` (see
  # compute_output_url_winners) and must not write it.
  private def collision_suppressed?(page : Models::Page, url_key : String) : Bool
    return false unless winners = @output_url_winners
    (winner = winners[url_key]?) ? winner != page.path : false
  end

  private def generate_redirect_page(
    page : Models::Page,
    site : Models::Site,
    output_dir : String,
    verbose : Bool = false,
  )
    redirect_url = page.redirect_to
    return unless redirect_url

    # Prefix a root-relative target with `base_url`'s path component, exactly
    # as generate_aliases does: without it, `redirect_to = "/about/"` on a
    # site deployed under `/repo/` sent readers to the domain root, which 404s.
    # `with_base_path` leaves http(s) and protocol-relative targets untouched,
    # so an intentional off-site redirect still works.
    redirect_url = site.config.with_base_path(redirect_url)
    return if collision_suppressed?(page, page.url)

    # Same refusal contract as the main page sink: a redirect stub is still a
    # published file, so a traversing URL must be refused loudly rather than
    # written to whatever `sanitize_path` collapses it to. `/../` collapsed to
    # `""`, which put the redirect stub on `<output_dir>/index.html` — on a
    # site without its own `content/index.md` that stub BECAME the homepage.
    url_path = url_output_path(page.url.lchop("/"))
    unless url_path
      Logger.warn "Not publishing #{page.path}: its URL #{page.url.inspect} cannot be written inside the output directory (a path segment traverses or escapes it). Rename the file or set an explicit `slug`/`path` in its front matter."
      note_unpublished_page
      return
    end
    candidate = File.join(output_dir, url_path, "index.html")
    output_path = Utils::OutputGuard.safe_output_path(candidate, output_dir)
    unless output_path
      Logger.warn "Skipping redirect outside output directory: #{candidate}"
      note_unpublished_page
      return
    end

    ensure_dir(Path[output_path].dirname.to_s)
    Hwaro::Utils::FileSafe.atomic_write(output_path, Utils::RedirectHtml.full_redirect(redirect_url))
    note_published_page
    Logger.action :create, output_path if verbose
  end

  private def generate_aliases(page : Models::Page, site : Models::Site, output_dir : String, verbose : Bool)
    own_url = normalize_alias_url(page.url)
    # The page's own output FILE, not just its URL string: `/about/`,
    # `/about//` and `/about/index.html` are three spellings of
    # `about/index.html`, and only the last one normalizes back to `own_url`.
    # A raw string compare therefore let `aliases = ["/about//"]` through on
    # the page whose url is `/about/`, and the self-redirect stub was written
    # straight over that page's own rendered HTML — exit 0, no warning, the
    # body gone. (`compute_output_url_winners` cannot catch it either: the
    # alias and the page share a path, so it reads as the same claimant.)
    # nil = the page's URL is unpublishable, in which case there is no file
    # for an alias to destroy and only the string compare applies.
    own_file_key = Utils::PathUtils.output_file_key(own_url)
    page.aliases.each do |alias_path|
      norm = normalize_alias_url(alias_path)
      # An alias pointing at the page's own URL would overwrite the real
      # content with a redirect stub to itself.
      next if norm == own_url
      next if own_file_key && Utils::PathUtils.output_file_key(norm) == own_file_key
      next if collision_suppressed?(page, norm)

      alias_clean = url_output_path(alias_path.lchop("/"))
      unless alias_clean
        Logger.warn "Skipping alias #{alias_path.inspect} on #{page.path}: a path segment would escape the output directory."
        note_unpublished_page
        next
      end
      # An alias that already names an HTML file (`/legacy.html`,
      # `/old/index.html`) is written to that exact path; only "pretty"
      # aliases (`/old/`) get an `index.html` appended. Previously every
      # alias got `/index.html` tacked on, so `/legacy/index.html` became
      # the directory `legacy/index.html/` with an `index.html` inside.
      dest_path = if alias_clean.ends_with?(".html") || alias_clean.ends_with?(".htm")
                    File.join(output_dir, alias_clean)
                  else
                    File.join(output_dir, alias_clean, "index.html")
                  end
      next unless Utils::OutputGuard.within_output_dir?(dest_path, output_dir)

      ensure_dir(File.dirname(dest_path))

      # Prefix the page's root-relative URL with `base_url`'s path component so
      # the redirect still resolves when the site is deployed under a subpath
      # (e.g. GitHub Pages project sites at `/repo/`). `page.url` may arrive
      # without a leading slash (see sitemap), so normalize before prefixing;
      # `with_base_path` is a no-op for a domain-root deployment.
      target = page.url.starts_with?('/') ? page.url : "/#{page.url}"
      redirect_url = site.config.with_base_path(target)
      Hwaro::Utils::FileSafe.atomic_write(dest_path, Utils::RedirectHtml.simple_redirect(redirect_url))
      Logger.action :create, dest_path, Logger::Role::Warn if verbose
    end
  end
end
