{
  description = "A fast, lightweight static site generator built with Crystal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      lib = nixpkgs.lib;

      # shard.yml is the single source of truth for both the package version and
      # the minimum compiler, so a release bump or a Crystal requirement bump
      # cannot leave this file behind (scripts/version_update.cr therefore does
      # not rewrite it).
      shardYml = lib.splitString "\n" (builtins.readFile ./shard.yml);

      shardField =
        key:
        let
          prefix = "${key}: ";
          hits = builtins.filter (l: lib.hasPrefix prefix l) shardYml;
        in
        if hits == [ ] then
          throw "hwaro: no `${key}:` line in shard.yml"
        else
          lib.removePrefix prefix (builtins.head hits);

      version = shardField "version";

      # `crystal: ">= 1.21.0"` -> `1.21.0`. shards also accepts `~>` and
      # comma-separated constraints; rather than guess at those, refuse them --
      # a silently mis-parsed constraint would pick the wrong compiler.
      crystalMinimum =
        let
          raw = lib.removeSuffix "\"" (lib.removePrefix "\"" (shardField "crystal"));
          parsed = builtins.match "^>= ([0-9]+(\\.[0-9]+)*)$" raw;
        in
        if parsed == null then
          throw "hwaro: flake.nix only understands a `crystal: \">= X.Y.Z\"` constraint in shard.yml, got `${raw}`"
        else
          builtins.head parsed;

      # hwaro needs Crystal >= 1.21: src/main.cr resizes the default
      # `Fiber::ExecutionContext`, which does not exist before that release.
      # nixpkgs still ships 1.19 (checked 2026-08-30), so until it catches up we
      # build against the official upstream release tarball -- the same artifact
      # nixpkgs uses to bootstrap its own Crystal.
      #
      # Once `pkgs.crystal.version` reaches crystalMinimum the pin stops being
      # selected and this whole block can be deleted.
      crystalRelease = {
        release = "1.21.0";
        build = "1";
        # nix store prefetch-file <url>
        assets = {
          x86_64-linux = {
            arch = "linux-x86_64";
            hash = "sha256-dEVh7jzuGwbRBs+a6ZuAZLTgF1GKxBTW3SPPr+NlYMk=";
          };
          aarch64-linux = {
            arch = "linux-aarch64";
            hash = "sha256-TzDan/CD3EhWUuPZsE1+gsxMSftuirO6x2y94k2WB3g=";
          };
          # No x86_64-darwin: nixpkgs-unstable dropped that platform in 26.11
          # and throws on evaluation, so listing it would only produce a broken
          # flake output. Upstream ships a universal macOS tarball, so adding it
          # back is a one-line change if this flake ever tracks a release branch
          # that still supports Intel Macs.
          aarch64-darwin = {
            arch = "darwin-universal";
            hash = "sha256-f8SvVrDLXH6lcD90TGYpuxn/Nro6u/Iy1Q5Aw5og7hY=";
          };
        };
      };

      systems = builtins.attrNames crystalRelease.assets;
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        asset = crystalRelease.assets.${system};

        # Upstream ships a self-contained toolchain (its own pcre2, bdwgc,
        # libyaml and libffi live under embedded/), so unpacking is enough --
        # `buildCommand` deliberately skips fixupPhase, which would otherwise
        # try to strip and patchelf statically linked musl binaries.
        pinnedCrystal = pkgs.stdenv.mkDerivation (finalAttrs: {
          pname = "crystal-upstream";
          version = crystalRelease.release;

          src = pkgs.fetchurl {
            url = "https://github.com/crystal-lang/crystal/releases/download/${crystalRelease.release}/crystal-${crystalRelease.release}-${crystalRelease.build}-${asset.arch}.tar.gz";
            inherit (asset) hash;
          };

          buildCommand = ''
            mkdir -p $out
            tar --strip-components=1 -C $out -xf ${finalAttrs.src}
            patchShebangs $out/bin
            # The macOS tarball keeps shards under embedded/bin and exposes only
            # bin/crystal; the Linux ones ship both in bin/. The dev shell needs
            # shards on PATH either way.
            [ -e $out/bin/shards ] || ln -s ../embedded/bin/shards $out/bin/shards
          '';

          meta = {
            description = "Official Crystal ${crystalRelease.release} release build";
            homepage = "https://crystal-lang.org/";
            license = lib.licenses.asl20;
            mainProgram = "crystal";
            platforms = systems;
          };
        });

        useNixpkgsCrystal = lib.versionAtLeast pkgs.crystal.version crystalMinimum;

        crystal =
          if useNixpkgsCrystal then
            pkgs.crystal
          else if lib.versionAtLeast crystalRelease.release crystalMinimum then
            pinnedCrystal
          else
            throw "hwaro: shard.yml requires Crystal >= ${crystalMinimum}, but nixpkgs has ${pkgs.crystal.version} and flake.nix pins ${crystalRelease.release}; bump crystalRelease (URLs + hashes) or drop the pin.";

        # pinnedCrystal carries its own matching shards; nixpkgs' crystal does not.
        toolchain = [ crystal ] ++ lib.optional useNixpkgsCrystal pkgs.shards;

        # nixpkgs' builder, retargeted at whichever compiler was selected above.
        buildCrystalPackage = pkgs.crystal.buildCrystalPackage.override { inherit crystal; };

        # Crystal's stdlib pulls these in through `compress/*`, `openssl` and
        # `xml`, and neither toolchain supplies them: the pinned tarball bundles
        # only pcre2/bdwgc/libyaml/libffi, and nixpkgs' crystal wrapper exports
        # its own build inputs, not ours.
        linkLibs = [
          pkgs.zlib
          pkgs.openssl
          pkgs.libxml2
        ]
        ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.libiconv;

        # Everything the compiler reads, and nothing else: docs/ and spec/ are
        # ~17MB that cannot change the binary, so leaving them out keeps
        # `nix build` cached across documentation work. CHANGELOG.md is left out
        # for the same reason -- it is rewritten on every release and would
        # invalidate the derivation for a byte-identical binary. README.md and
        # LICENSE stay because nixpkgs' installPhase copies them to
        # $out/share/doc.
        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./src
            ./shard.yml
            ./shard.lock
            ./README.md
            ./LICENSE
          ];
        };

        hwaro = buildCrystalPackage {
          pname = "hwaro";
          inherit version src;

          # Without this the default "make" builder runs, and `crystalBinaries`
          # below is silently ignored.
          format = "crystal";

          # Regenerate with `just nix-update` whenever shard.lock changes.
          shardsFile = ./shards.nix;

          # Kept in sync with `targets.hwaro.main` in shard.yml by hand -- Nix
          # has no YAML parser at eval time. A stale path fails the build loudly
          # ("Error: file 'src/main.cr' does not exist"), it cannot build the
          # wrong thing silently.
          crystalBinaries.hwaro = {
            src = "src/main.cr";
            # release-binary.yml also passes --static on Linux; a Nix build
            # links against the store closure instead, so that flag is omitted.
            options = [
              "--release"
              "--no-debug"
            ];
          };

          buildInputs = linkLibs;

          # `crystal spec` needs the spec/ tree and shells out to the built
          # binary over a real socket; CI covers it on every push instead.
          doCheck = false;

          meta = {
            description = "A fast, lightweight static site generator built with Crystal";
            homepage = "https://github.com/hahwul/hwaro";
            changelog = "https://github.com/hahwul/hwaro/blob/main/CHANGELOG.md";
            license = lib.licenses.mit;
            mainProgram = "hwaro";
            platforms = systems;
          };
        };
      in
      {
        packages = {
          default = hwaro;
          inherit hwaro;
        };

        apps.default = {
          type = "app";
          program = lib.getExe hwaro;
          meta = {
            inherit (hwaro.meta)
              description
              homepage
              license
              mainProgram
              ;
          };
        };

        # `nix flake check` builds the package (and runs its --help smoke test).
        checks.hwaro = hwaro;

        formatter = pkgs.nixfmt-tree;

        devShells.default = pkgs.mkShell {
          packages = toolchain ++ [
            pkgs.crystal2nix
            pkgs.just
            pkgs.git
            pkgs.pkg-config
          ];

          # `just build` shells out to the real `shards`, so the shell needs the
          # same link-time libraries the package does.
          buildInputs = linkLibs;

          # stderr, so `nix develop -c <cmd>` stays pipeable.
          shellHook = ''
            {
              echo "hwaro dev shell — $(crystal --version | head -n1)"
              echo "  just build       # shards install && shards build"
              echo "  just test        # crystal spec"
              echo "  just nix-update  # regenerate shards.nix after shard.lock changes"
            } >&2
          '';
        };
      }
    )
    // {
      # Lets downstream flakes do `pkgs.hwaro` after adding this overlay. It
      # reuses this flake's own build (including the pinned compiler) rather
      # than re-resolving against the consumer's nixpkgs.
      overlays.default =
        _final: prev:
        let
          inherit (prev.stdenv.hostPlatform) system;
        in
        {
          hwaro =
            self.packages.${system}.hwaro
              or (throw "hwaro: no package for ${system}; supported systems are ${lib.concatStringsSep ", " systems}");
        };
    };
}
