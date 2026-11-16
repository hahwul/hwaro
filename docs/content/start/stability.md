+++
title = "Stability"
description = "What a 1.x release keeps working, what it may change, and how to choose which releases your site follows"
weight = 7
toc = true
+++

From 1.0, Hwaro follows [semantic versioning](https://semver.org/). A site that builds with one 1.x release builds the same way with every later 1.x release, apart from the exceptions listed on this page. A change that breaks that promise waits for 2.0.

## What 1.x keeps working

These are what a site and its scripts depend on. A 1.x release adds to them and does not remove from them or change what they mean.

| Area | Covered |
|---|---|
| `config.toml` | Every documented key: its name, type, meaning and default |
| Content | Documented front matter keys, the documented Markdown syntax and extensions, and the shortcode call syntax |
| Templates | Documented variables, filters, functions and tests, and the [escaping rules](/templates/syntax/#html-escaping) |
| Output | The URL of every page, section, taxonomy page, alias and feed, the names and locations of generated files (`sitemap.xml`, feeds, `search.json`, `robots.txt`, `llms.txt`), and heading ids |
| Command line | Commands and flags, [exit codes and error codes](/start/cli/#error-taxonomy), the fields of `--json` output, and lines documented as machine-readable (`hwaro serve: ready url=…`) |
| GitHub Action | Its inputs, and what each one does |

A new key, flag, filter or `--json` field can appear in any minor release. Code that reads JSON output should ignore fields it does not know.

## What can change in any release

- **Wrong output.** A bug fix changes what the bug produced. If a page was rendered incorrectly, a patch release may render it differently. The release notes list every fix that changes output.
- **Human-readable text.** The wording and layout of log lines, warnings and error messages, and the look of the terminal output. Parse `--json` output and exit codes, not messages. A release may also add warnings.
- **What `hwaro init` writes.** Scaffold templates, styles and sample content improve over time. A site that already exists is not touched.
- **Internal files.** Everything under `.hwaro/` (the build cache, the `hwaro serve` output). It can be deleted at any time and is rebuilt.
- **Rendering details outside the documented surface.** The exact markup of syntax-highlighted code, the pixels of generated Open Graph images, and whitespace in generated HTML.
- **Performance.** Build time and memory use are not part of the contract, though a regression is treated as a bug.
- **Undocumented behaviour.** If these docs do not describe it, do not rely on it. Open an issue if you need it documented.
- **Building from source.** The minimum Crystal version can rise in a minor release. Hwaro's source is not a library: its Crystal classes and modules have no stable API.

A security fix can change behaviour in a patch release when there is no other way to close the hole. The release notes say so.

## Deprecation

Before a documented feature is removed in the next major version, a 1.x release marks it deprecated: the build prints a warning that names the replacement, [`hwaro doctor`](/start/tools/doctor/) reports it, and the docs say what to use instead. The feature keeps working for the rest of 1.x.

A configuration key that a new major version no longer reads is not a silent no-op: the build warns and names the key, as 1.0 does for [`[plugins]`](/start/upgrading/#plugins-was-removed).

## Prereleases

A version with a suffix, such as `1.1.0-rc.1`, is a release candidate published for testing. It can still change before the final release, and it is not sent to Homebrew, AUR, Chocolatey, the snap `stable` channel or the `latest` container tag. Install one from its [GitHub release](https://github.com/hahwul/hwaro/releases) page, the container tag of the same name, or the snap `candidate` channel.

## Choosing what your site follows

| You write | You get |
|---|---|
| `hahwul/hwaro@v1`, `ghcr.io/hahwul/hwaro:1` | Every 1.x release. This is what `hwaro tool platform` generates |
| `hahwul/hwaro@v1.2.3`, `ghcr.io/hahwul/hwaro:1.2.3` | That release, until you change it |
| `ghcr.io/hahwul/hwaro:1.2` | Patch releases of 1.2 |
| `ghcr.io/hahwul/hwaro:latest` | The newest release, including the next major version |
| `hahwul/hwaro@main`, `ghcr.io/hahwul/hwaro:main` | The development branch. Nothing on this page applies to it |

Homebrew, AUR, Chocolatey and snap install the newest release. To hold a site on one version there, keep the version you built with in your CI configuration instead: a pinned action or image builds the same way on every run.
