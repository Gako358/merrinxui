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

          googleFont =
            path: hash:
            pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/google/fonts/47d54ca1ebb14fd864695f1d39dc734f39017c33/ofl/${path}";
              name = builtins.replaceStrings [ "/" "%5B" "%5D" ] [ "-" "" "" ] path;
              inherit hash;
            };

          googleFonts = {
            "PT_Sans-Narrow-Web-Regular.ttf" =
              googleFont "ptsansnarrow/PT_Sans-Narrow-Web-Regular.ttf" "sha256-QQLt2gMFkWN3GGnSWN9UrIVjxAj6bp73Wy3cheq+pvQ=";
            "PT_Sans-Narrow-Web-Bold.ttf" =
              googleFont "ptsansnarrow/PT_Sans-Narrow-Web-Bold.ttf" "sha256-5p2DvPW9ZHiStOKyL1CY2r1VyYlBNRMZdyL8FW+58A4=";
            "PTSansNarrow-OFL.txt" =
              googleFont "ptsansnarrow/OFL.txt" "sha256-J1jPeocoJ/OWYc+MwkGIETwDBEeu+1ynFFmTZQB2yow=";
            "RussoOne-Regular.ttf" =
              googleFont "russoone/RussoOne-Regular.ttf" "sha256-vAq8xmC9i3rTAA7LKJiifFiimlD37IFlL6EudRSNCd8=";
            "RussoOne-OFL.txt" =
              googleFont "russoone/OFL.txt" "sha256-OsEwFUlSPZhh/tyhKHHyTldfvSbVIGMvwAuoSbRx0nU=";
            "Changa-VF.ttf" =
              googleFont "changa/Changa%5Bwght%5D.ttf" "sha256-fE96FNS3CsiBbqjfOgsSeu5MX1r3I5rKKv7MhN3H9NM=";
            "Changa-OFL.txt" =
              googleFont "changa/OFL.txt" "sha256-axLI1Be7dm+gF9EWHHygUDkoF6fuy/MRD8KoYWVkuVY=";
            "CinzelDecorative-Regular.ttf" =
              googleFont "cinzeldecorative/CinzelDecorative-Regular.ttf" "sha256-W4Yr4ykQOtKHoQ8KU+J6QOjMUZmZJT8aAiPi3DMLELg=";
            "CinzelDecorative-Bold.ttf" =
              googleFont "cinzeldecorative/CinzelDecorative-Bold.ttf" "sha256-6FTmijiKpQ10KkQVwa5cF6YX73lWyVpwAh0KSkTyBRg=";
            "CinzelDecorative-OFL.txt" =
              googleFont "cinzeldecorative/OFL.txt" "sha256-Hl1mYDZt3Pyk8vwQ4qz7qfpNl9QK7IDX2/1B1zCkIK4=";
            "Exo-VF.ttf" =
              googleFont "exo/Exo%5Bwght%5D.ttf" "sha256-Lwj4GPETWsV5gDDAvKJSwIRa9cVN/hcqXHT73WiENEU=";
            "Exo-OFL.txt" = googleFont "exo/OFL.txt" "sha256-EVnqcu0ffnVBzqNaDezkjSq7AxfXxw91pIL5STI4Knc=";
            "BarlowCondensed-Regular.ttf" =
              googleFont "barlowcondensed/BarlowCondensed-Regular.ttf" "sha256-WDzsXaO4S8TcfJxy4qVlyU005DFRixnX4lC3gwrV+ZY=";
            "BarlowCondensed-Medium.ttf" =
              googleFont "barlowcondensed/BarlowCondensed-Medium.ttf" "sha256-JivRQyks5HnuDNCaQrR6sXP8qOnG617QtcioRbw3HRc=";
            "BarlowCondensed-SemiBold.ttf" =
              googleFont "barlowcondensed/BarlowCondensed-SemiBold.ttf" "sha256-e2GdFLwjJ1CanvMrCJD3CWJvfsyf9hGRwqQxTFSZ0tk=";
            "BarlowCondensed-Bold.ttf" =
              googleFont "barlowcondensed/BarlowCondensed-Bold.ttf" "sha256-5HZWLsnB4WzxZHWJW1EfCMgE9DjMmp+ApE6lCg7rW2U=";
            "BarlowCondensed-OFL.txt" =
              googleFont "barlowcondensed/OFL.txt" "sha256-GG11DrSWpMF6djhfgr5q6irBzy3gdKgR1jeGzzdOpz8=";
          };

          statusbarTextures = pkgs.writeText "statusbars.py" ''
            import math
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


            def minimal(x, y):
                if y == H - 1:
                    return 0.7
                return 0.97 - 0.07 * y / (H - 1)


            def soft(x, y):
                return 0.72 + 0.28 * math.cos(math.pi * (y / (H - 1) - 0.5))


            def glass(x, y):
                if y == 0:
                    return 1.0
                if y < H // 2:
                    return 0.98 - 0.12 * y / (H // 2 - 1)
                return 0.8 + 0.08 * (y - H // 2) / (H // 2 - 1)


            def gradient_down(x, y):
                return 1.0 - 0.55 * y / (H - 1)


            def gradient_up(x, y):
                return 0.45 + 0.55 * y / (H - 1)


            def gradient_right(x, y):
                return 0.45 + 0.55 * x / (W - 1)


            def gradient_left(x, y):
                return 1.0 - 0.55 * x / (W - 1)


            def sharp(x, y):
                return 1.0 if y < H * 0.4 else 0.72


            def diamonds(x, y):
                d = abs(x % 16 - 8) + abs(y % 16 - 8)
                return 1.0 if d < 6 else 0.82


            def plating(x, y):
                noise = ((x * 1103515245 + 12345) >> 8 & 255) / 255
                return (0.84 + 0.1 * noise) * (1.0 - 0.12 * y / (H - 1))


            def divide(x, y):
                if x % 32 == 0:
                    return 0.55
                return 0.92 - 0.1 * y / (H - 1)


            def sheer(x, y):
                return 1.0, 0.55


            def write(path, shade):
                header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x28)
                rows = bytearray()
                for y in range(H):
                    for x in range(W):
                        s = shade(x, y)
                        v, a = s if isinstance(s, tuple) else (s, 1.0)
                        v = max(0, min(255, round(255 * v)))
                        rows += bytes((v, v, v, round(255 * a)))
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
                ("Minimal", minimal),
                ("Soft", soft),
                ("Glass", glass),
                ("GradientDown", gradient_down),
                ("GradientUp", gradient_up),
                ("GradientRight", gradient_right),
                ("GradientLeft", gradient_left),
                ("Sharp", sharp),
                ("Diamonds", diamonds),
                ("Plating", plating),
                ("Divide", divide),
                ("Sheer", sheer),
            ]:
                write(f"{out}/{name}.tga", shade)
          '';

          soundEffects = pkgs.writeText "sounds.py" ''
            import math
            import struct
            import sys
            import wave

            RATE = 44100


            def tone(freq, length, decay, partials=((1.0, 1.0),)):
                samples = []
                for i in range(int(RATE * length)):
                    t = i / RATE
                    env = math.exp(-t / decay) * min(1.0, t / 0.005)
                    v = sum(a * math.sin(2 * math.pi * freq * r * t) for r, a in partials)
                    samples.append(env * v)
                return samples


            def silence(length):
                return [0.0] * int(RATE * length)


            def chime():
                return tone(659.25, 0.18, 0.08, ((1, 1), (2, 0.3))) + tone(880.0, 0.5, 0.15, ((1, 1), (2, 0.3)))


            def ding():
                return tone(1046.5, 0.7, 0.18, ((1, 1), (2, 0.2), (3, 0.08)))


            def bell():
                return tone(523.25, 1.4, 0.4, ((1, 1), (2.0, 0.5), (2.76, 0.35), (5.4, 0.15)))


            def alert():
                beep = tone(880.0, 0.08, 1.0, ((1, 1), (3, 0.25)))
                return beep + silence(0.06) + beep + silence(0.06) + beep


            def blip():
                return tone(1318.5, 0.09, 0.04)


            def write(path, samples):
                peak = max(abs(s) for s in samples) or 1.0
                frames = b"".join(struct.pack("<h", int(32767 * 0.8 * s / peak)) for s in samples)
                with wave.open(path, "wb") as w:
                    w.setnchannels(1)
                    w.setsampwidth(2)
                    w.setframerate(RATE)
                    w.writeframes(frames)


            out = sys.argv[1]
            for name, make in [
                ("Chime", chime),
                ("Ding", ding),
                ("Bell", bell),
                ("Alert", alert),
                ("Blip", blip),
            ]:
                write(f"{out}/{name}.wav", make())
          '';

          addonMedia =
            pkgs.runCommand "merrinxui-media"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.python3Packages.fonttools
                  pkgs.vorbis-tools
                ];
              }
              ''
                mkdir -p $out/Fonts $out/Textures $out/Sounds
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
                ${lib.concatStrings (
                  lib.mapAttrsToList (name: src: ''
                    cp ${src} "$out/Fonts/${name}"
                  '') googleFonts
                )}
                for family in Changa Exo; do
                  fonttools varLib.instancer -q -o "$out/Fonts/$family-Regular.ttf" "$out/Fonts/$family-VF.ttf" wght=400
                  fonttools varLib.instancer -q -o "$out/Fonts/$family-Bold.ttf" "$out/Fonts/$family-VF.ttf" wght=700
                  rm "$out/Fonts/$family-VF.ttf"
                done

                python3 ${statusbarTextures} $out/Textures

                mkdir wav
                python3 ${soundEffects} wav
                for f in wav/*.wav; do
                  oggenc -Q -s 1 -q 5 -o "$out/Sounds/$(basename "$f" .wav).ogg" "$f"
                done
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
            done < <(grep -oE '"(Fonts|Textures|Sounds)\\\\[^"]+"' "$out/MerrinxUI/Util/Media.lua" | tr -d '"')
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
