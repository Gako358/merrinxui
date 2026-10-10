{
  description = "MerrinxUI - World of Warcraft: Forever addon suite";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ace3 = {
      url = "github:WoWUIDev/Ace3";
      flake = false;
    };

    librangecheck = {
      url = "github:WeakAuras/LibRangeCheck-3.0";
      flake = false;
    };
  };

  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { system, lib, ... }:
        let
          pkgs = import nixpkgs { inherit system; };

          pre-commit-check = inputs.git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              statix.enable = true;
              deadnix.enable = true;
              nil.enable = true;
              nixfmt.enable = true;
              luacheck = {
                enable = true;
                package = pkgs.lua51Packages.luacheck;
              };
              stylua.enable = true;
            };
          };

          addonLibs = pkgs.runCommand "merrinxui-libs" { } ''
            mkdir -p $out
            for d in LibStub CallbackHandler-1.0 AceAddon-3.0 AceConsole-3.0 AceEvent-3.0 AceDB-3.0 AceDBOptions-3.0 AceGUI-3.0 AceConfig-3.0; do
              cp -r ${inputs.ace3}/$d $out/$d
            done
            cp ${inputs.ace3}/LICENSE.txt $out/Ace3-LICENSE.txt

            cp -r ${inputs.librangecheck}/LibRangeCheck-3.0 $out/LibRangeCheck-3.0
            cp ${inputs.librangecheck}/LICENSE $out/LibRangeCheck-3.0-LICENSE.txt
          '';

          merrinxui = pkgs.runCommand "merrinxui" { } ''
            mkdir -p "$out/MerrinxUI"
            cp -r ${./MerrinxUI}/. "$out/MerrinxUI"/
            cp -r ${addonLibs} "$out/MerrinxUI/Libs"
            chmod -R u+w "$out/MerrinxUI"

            toc="$out/MerrinxUI/MerrinxUI.toc"
            while IFS= read -r raw || [ -n "$raw" ]; do
              line=$(printf '%s' "$raw" | tr -d '\r')
              line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
              case "$line" in
                "" | "#"*) continue ;;
              esac
              rel=$(printf '%s' "$line" | tr '\\' '/')
              if [ ! -e "$out/MerrinxUI/$rel" ]; then
                echo "missing: $rel"
                exit 1
              fi
            done < "$toc"

            embeds="$out/MerrinxUI/embeds.xml"
            while IFS= read -r ref || [ -n "$ref" ]; do
              rel=$(printf '%s' "$ref" | tr '\\' '/')
              if [ ! -e "$out/MerrinxUI/$rel" ]; then
                echo "missing: $rel"
                exit 1
              fi
            done < <(grep -o 'file="[^"]*"' "$embeds" | sed 's/^file="//; s/"$//')
          '';

          lua-syntax = pkgs.runCommand "merrinxui-lua-syntax" { nativeBuildInputs = [ pkgs.lua5_1 ]; } ''
            find ${./MerrinxUI} -name '*.lua' -exec luac -p {} +
            touch "$out"
          '';

          busted =
            let
              source = lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions [
                  ./MerrinxUI
                  ./spec
                ];
              };
            in
            pkgs.runCommand "merrinxui-busted"
              {
                nativeBuildInputs = [
                  pkgs.lua5_1
                  pkgs.lua51Packages.busted
                ];
              }
              ''
                export HOME="$TMPDIR"
                cd ${source}
                busted spec
                touch "$out"
              '';

          release = pkgs.runCommand "merrinxui-release" { nativeBuildInputs = [ pkgs.zip ]; } ''
            cp -r ${merrinxui}/MerrinxUI .
            chmod -R u+w MerrinxUI
            find MerrinxUI -exec touch -h -d '1980-01-02T00:00:00Z' {} +
            mkdir -p $out
            find MerrinxUI -type f | LC_ALL=C sort | zip -X -D -@ $out/MerrinxUI.zip
          '';
        in
        {
          formatter = pkgs.nixfmt;

          packages = {
            inherit merrinxui release;
            default = merrinxui;
          };

          checks = {
            inherit
              pre-commit-check
              merrinxui
              lua-syntax
              busted
              ;
          };

          devShells.default = pkgs.mkShell {
            inherit (pre-commit-check) shellHook;
            packages =
              pre-commit-check.enabledPackages
              ++ (with pkgs; [
                lua5_1
                lua51Packages.luacheck
                lua51Packages.busted
                stylua
                lua-language-server
                zip
                unzip
              ]);
          };
        };
    };
}
