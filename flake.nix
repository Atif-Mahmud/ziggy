{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig2nix = {
      url = "github:Cloudef/zig2nix";
    };
  };

  outputs = { self, zig2nix, nixpkgs, ... }: let
    # This pre-built zls derivation is kept from your original flake.
    # It will only be available on x86_64-linux dev shells.
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    flake-utils = zig2nix.inputs.flake-utils;
    zls-prebuilt = pkgs.stdenv.mkDerivation {
      pname = "zls-prebuilt";
      version = "0.14.1";

      src = pkgs.fetchurl {
        url = "https://github.com/llogick/zigscient/releases/download/0.14.1/zigscient-x86_64-linux.zip";
        sha256 = "jYaz+z0aM2YNl8FMNEq6A0R3eMnuVjfwh3v6yY/W3nc=";
      };

      nativeBuildInputs = [ pkgs.unzip ];
      sourceRoot = ".";

      installPhase = ''
        mkdir -p $out/bin
        cp ./zigscient-x86_64-linux $out/bin/zls
        chmod +x $out/bin/zls
      '';

      meta = {
        description = "The zls language server for Zig, pre-built from GitHub releases";
        homepage = "https://github.com/llogick/zigscient";
        license = pkgs.lib.licenses.mit;
        platforms = [ "x86_64-linux" ];
        sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
      };
    };
  # The eachDefaultSystem structure provides broad platform support.
  in (flake-utils.lib.eachDefaultSystem (system: let
    env = zig2nix.outputs.zig-env.${system} { zig = zig2nix.outputs.packages.${system}.zig-latest; };
    # zig-deps = import ./build.zig.zon.nix {
    #   lib = env.pkgs.lib;
    #   linkFarm = env.pkgs.linkFarm;
    #   fetchurl = env.pkgs.fetchurl;
    #   fetchgit = env.pkgs.fetchgit;
    #   runCommandLocal = env.pkgs.runCommandLocal;
    #   zig = env.zig; # Pass the zig compiler from the environment
    # };
  in with builtins; with env.pkgs.lib; rec {
    packages.ziggy-foreign = env.package {
      name = "ziggy-foreign";
      src = cleanSource ./.;
      nativeBuildInputs = with env.pkgs; [];
      buildInputs = with env.pkgs; [];
      zigPreferMusl = true;
    };

    # This is the standard Nix-friendly package (linked with glibc).
    packages.ziggy = packages.ziggy-foreign.override (attrs: {
      name = "ziggy";
      zigPreferMusl = false;
      zigWrapperBins = with env.pkgs; [];
      zigWrapperLibs = attrs.buildInputs or [];
    });

    # Sets `nix build .` to build the standard 'ziggy' package.
    packages.default = packages.ziggy;

    # The rich set of apps is preserved.
    # For bundling with `nix bundle`.
    apps.bundle = {
      type = "app";
      # NOTE: This assumes your `build.zig` produces an executable named 'ziggy'.
      program = "${packages.ziggy-foreign}/bin/ziggy";
    };

    # `nix run .`
    apps.default = env.app [] "zig build run -- \"$@\"";
    # `nix run .#build`
    apps.build = env.app [] "zig build \"$@\"";
    # `nix run .#test`
    apps.test = env.app [] "zig build test -- \"$@\"";
    # `nix run .#docs`
    apps.docs = env.app [] "zig build docs -- \"$@\"";
    # `nix run .#zig2nix`
    apps.zig2nix = env.app [] "zig2nix \"$@\"";

    # `nix develop`
    # The dev shell now correctly references the renamed `ziggy` package.
    devShells.default = env.mkShell {
      nativeBuildInputs = [
        zls-prebuilt
      ]
      ++ packages.ziggy.nativeBuildInputs
      ++ packages.ziggy.buildInputs
      ++ packages.ziggy.zigWrapperBins
      ++ packages.ziggy.zigWrapperLibs;
    };
  })) // {
    formatter = flake-utils.lib.genAttrs flake-utils.lib.defaultSystems (system:
      nixpkgs.legacyPackages.${system}.nixfmt-rfc-style
    );
  };
}
