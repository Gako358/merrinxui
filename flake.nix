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

    wow-api = {
      url = "github:Ketho/vscode-wow-api";
      flake = false;
    };

    libsharedmedia = {
      url = "file+https://repos.curseforge.com/wow/libsharedmedia-3-0/!svn/bc/182/trunk/LibSharedMedia-3.0/LibSharedMedia-3.0.lua";
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

            mkdir -p $out/LibSharedMedia-3.0
            cp ${inputs.libsharedmedia} $out/LibSharedMedia-3.0/LibSharedMedia-3.0.lua
            cp ${pkgs.spdx-license-list-data.text}/text/LGPL-2.1-only.txt $out/LibSharedMedia-3.0-LICENSE.txt
          '';

          statusbarTextures = pkgs.writeText "statusbars.py" ''
            import struct
            import sys

            W, H = 256, 32


            def smooth(x, y):
                return 1.0 - 0.28 * y / (H - 1)


            def gloss(x, y):
                if y < H // 2:
                    return 1.0 - 0.1 * y / (H // 2 - 1)
                return 0.78 - 0.08 * (y - H // 2) / (H // 2 - 1)


            def matte(x, y):
                if y == 0:
                    return 1.0
                if y == H - 1:
                    return 0.6
                return 0.88


            def fade(x, y):
                return 0.7 + 0.3 * x / (W - 1)


            def striped(x, y):
                base = 1.0 if ((x + y) // 8) % 2 == 0 else 0.84
                return base * (1.0 - 0.15 * y / (H - 1))


            def inset(x, y):
                d = abs(y - (H - 1) / 2) / ((H - 1) / 2)
                return 1.0 - 0.35 * d * d


            def write(path, shade):
                header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x28)
                rows = bytearray()
                for y in range(H):
                    for x in range(W):
                        v = max(0, min(255, round(255 * shade(x, y))))
                        rows += bytes((v, v, v, 255))
                with open(path, "wb") as f:
                    f.write(header + rows)


            out = sys.argv[1]
            for name, shade in [
                ("Smooth", smooth),
                ("Gloss", gloss),
                ("Matte", matte),
                ("Fade", fade),
                ("Striped", striped),
                ("Inset", inset),
            ]:
                write(f"{out}/{name}.tga", shade)
          '';

          addonMedia = pkgs.runCommand "merrinxui-media" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            mkdir -p $out/Fonts $out/Textures
            truetype() { cp "$1/share/fonts/truetype/$2" $out/Fonts/; }
            for f in Roboto-Regular Roboto-Medium Roboto-Bold RobotoCondensed-Regular RobotoCondensed-Bold; do
              truetype ${pkgs.roboto} $f.ttf
            done
            for f in FiraSans-Regular FiraSans-Medium FiraSans-Bold FiraSansCondensed-Regular FiraSansCondensed-Medium; do
              truetype ${pkgs.fira-sans} $f.ttf
            done
            for f in Ubuntu-R Ubuntu-M Ubuntu-B Ubuntu-C; do
              truetype ${pkgs.ubuntu-classic} ubuntu/$f.ttf
            done
            for f in Lato-Regular Lato-Bold Lato-Black; do
              cp ${pkgs.lato}/share/fonts/lato/$f.ttf $out/Fonts/
            done
            for f in Poppins-Regular Poppins-SemiBold; do
              truetype ${pkgs.poppins} $f.ttf
            done
            for f in PT_Sans-Web-Regular PT_Sans-Web-Bold; do
              truetype ${pkgs.paratype-pt-sans} $f.ttf
            done
            for f in LiberationSans-Regular LiberationSans-Bold; do
              truetype ${pkgs.liberation_ttf} $f.ttf
            done
            cp ${pkgs.spdx-license-list-data.text}/text/OFL-1.1.txt $out/Fonts/OFL-1.1-LICENSE.txt
            cp ${pkgs.spdx-license-list-data.text}/text/Ubuntu-font-1.0.txt $out/Fonts/Ubuntu-font-1.0-LICENSE.txt

            python3 ${statusbarTextures} $out/Textures
          '';

          luarc = pkgs.writeText "luarc.json" (
            builtins.toJSON {
              runtime.version = "Lua 5.1";
              workspace = {
                library = [
                  "${inputs.wow-api}/Annotations/Core"
                  "${addonLibs}"
                ];
                checkThirdParty = false;
              };
            }
          );

          merrinxui = pkgs.runCommand "merrinxui" { } ''
            mkdir -p "$out/MerrinxUI"
            cp -r ${./MerrinxUI}/. "$out/MerrinxUI"/
            cp -r ${addonLibs} "$out/MerrinxUI/Libs"
            cp -r ${addonMedia} "$out/MerrinxUI/Media"
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

            while IFS= read -r ref; do
              rel=$(printf '%s' "$ref" | sed 's/\\\\/\//g')
              if [ ! -e "$out/MerrinxUI/Media/$rel" ]; then
                echo "missing: Media/$rel"
                exit 1
              fi
            done < <(grep -oE '"(Fonts|Textures)\\\\[^"]+"' "$out/MerrinxUI/Util/Media.lua" | tr -d '"')
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
            shellHook = pre-commit-check.shellHook + "\ninstall -m 644 ${luarc} .luarc.json\n";
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
