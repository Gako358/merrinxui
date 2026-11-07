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
            # Forever also returns secret GUIDs, but upstream only guards the cache key on Midnight.
            chmod u+w $out/LibRangeCheck-3.0/LibRangeCheck-3.0.lua
            substituteInPlace $out/LibRangeCheck-3.0/LibRangeCheck-3.0.lua \
              --replace-fail '(isMidnight and issecretvalue(guid) and unit or guid)' \
                '(issecretvalue(guid) and unit or guid)'

            mkdir -p $out/LibSharedMedia-3.0
            cp ${inputs.libsharedmedia} $out/LibSharedMedia-3.0/LibSharedMedia-3.0.lua
            cp ${pkgs.spdx-license-list-data.text}/text/LGPL-2.1-only.txt $out/LibSharedMedia-3.0-LICENSE.txt
          '';

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

          glyphIcons = pkgs.writeText "icons.py" ''
            import math
            import struct
            import sys

            S = 64
            SS = 4


            def seg(ax, ay, bx, by, w):
                def f(x, y):
                    dx, dy = bx - ax, by - ay
                    t = ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)
                    t = max(0.0, min(1.0, t))
                    px, py = ax + t * dx - x, ay + t * dy - y
                    return px * px + py * py <= (w / 2) ** 2

                return f


            def circle(cx, cy, r):
                return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


            def ring(cx, cy, r1, r2):
                return lambda x, y: r1 * r1 <= (x - cx) ** 2 + (y - cy) ** 2 <= r2 * r2


            def rect(x0, y0, x1, y1):
                return lambda x, y: x0 <= x <= x1 and y0 <= y <= y1


            def arc(cx, cy, r, w, a0, a1):
                def f(x, y):
                    d = math.hypot(x - cx, y - cy)
                    if abs(d - r) > w / 2:
                        return False
                    a = math.degrees(math.atan2(y - cy, x - cx)) % 360
                    return (a0 <= a <= a1) if a0 <= a1 else (a >= a0 or a <= a1)

                return f


            def poly(points):
                def f(x, y):
                    inside = False
                    n = len(points)
                    for i in range(n):
                        x1, y1 = points[i]
                        x2, y2 = points[(i + 1) % n]
                        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                            inside = not inside
                    return inside

                return f


            def union(*fs):
                return lambda x, y: any(f(x, y) for f in fs)


            def minus(a, *bs):
                return lambda x, y: a(x, y) and not any(b(x, y) for b in bs)


            def cog():
                def teeth(x, y):
                    d = math.hypot(x - 0.5, y - 0.5)
                    if not 0.26 <= d <= 0.42:
                        return False
                    a = math.degrees(math.atan2(y - 0.5, x - 0.5)) % 45
                    return a < 11 or a > 34

                return minus(union(ring(0.5, 0.5, 0.0, 0.32), teeth), circle(0.5, 0.5, 0.13))


            def sheet():
                outline = minus(rect(0.2, 0.14, 0.8, 0.86), rect(0.27, 0.21, 0.73, 0.79))
                lines = [seg(0.34, y, 0.66, y, 0.06) for y in (0.36, 0.5, 0.64)]
                return union(outline, *lines)


            def reset():
                head = poly([(0.66, 0.12), (0.86, 0.32), (0.6, 0.38)])
                return union(arc(0.5, 0.52, 0.28, 0.1, 300, 220), head)


            def plus(w):
                return union(seg(0.2, 0.5, 0.8, 0.5, w), seg(0.5, 0.2, 0.5, 0.8, w))


            def cross():
                return union(seg(0.24, 0.24, 0.76, 0.76, 0.1), seg(0.76, 0.24, 0.24, 0.76, 0.1))


            def lock(opened):
                body = rect(0.24, 0.46, 0.76, 0.86)
                keyhole = union(circle(0.5, 0.62, 0.06), rect(0.47, 0.62, 0.53, 0.74))
                if opened:
                    shackle = union(arc(0.5, 0.3, 0.17, 0.08, 180, 360), seg(0.67, 0.3, 0.67, 0.46, 0.08), seg(0.33, 0.3, 0.33, 0.34, 0.08))
                else:
                    shackle = union(arc(0.5, 0.4, 0.17, 0.08, 180, 360), seg(0.33, 0.4, 0.33, 0.46, 0.08), seg(0.67, 0.4, 0.67, 0.46, 0.08))
                return union(minus(body, keyhole), shackle)


            def grip():
                return union(*[seg(c - 0.86, 0.86, 0.86, c - 0.86, 0.07) for c in (1.22, 1.46, 1.7)])


            def width_arrows():
                return union(
                    seg(0.18, 0.5, 0.82, 0.5, 0.08),
                    poly([(0.1, 0.5), (0.3, 0.32), (0.3, 0.68)]),
                    poly([(0.9, 0.5), (0.7, 0.32), (0.7, 0.68)]),
                )


            def chevron():
                return union(seg(0.38, 0.24, 0.64, 0.5, 0.1), seg(0.64, 0.5, 0.38, 0.76, 0.1))


            def sword():
                return union(
                    seg(0.3, 0.7, 0.82, 0.18, 0.1),
                    seg(0.2, 0.6, 0.4, 0.8, 0.08),
                    seg(0.3, 0.7, 0.18, 0.82, 0.07),
                )


            def shield():
                return poly([(0.5, 0.1), (0.84, 0.24), (0.78, 0.6), (0.5, 0.9), (0.22, 0.6), (0.16, 0.24)])


            def warning():
                tri = poly([(0.5, 0.1), (0.9, 0.84), (0.1, 0.84)])
                return minus(tri, rect(0.46, 0.36, 0.54, 0.62), circle(0.5, 0.72, 0.045))


            def crosshair():
                return union(
                    ring(0.5, 0.5, 0.2, 0.28),
                    seg(0.5, 0.08, 0.5, 0.3, 0.07),
                    seg(0.5, 0.7, 0.5, 0.92, 0.07),
                    seg(0.08, 0.5, 0.3, 0.5, 0.07),
                    seg(0.7, 0.5, 0.92, 0.5, 0.07),
                    circle(0.5, 0.5, 0.06),
                )


            def forbidden():
                return union(ring(0.5, 0.5, 0.27, 0.37), seg(0.3, 0.3, 0.7, 0.7, 0.1))


            def sparkle():
                pts = []
                for i in range(8):
                    a = math.radians(i * 45 - 90)
                    r = 0.42 if i % 2 == 0 else 0.12
                    pts.append((0.5 + r * math.cos(a), 0.5 + r * math.sin(a)))
                return poly(pts)


            def skull():
                head = union(circle(0.5, 0.42, 0.3), rect(0.34, 0.5, 0.66, 0.84))
                return minus(
                    head,
                    circle(0.39, 0.44, 0.075),
                    circle(0.61, 0.44, 0.075),
                    poly([(0.5, 0.54), (0.45, 0.64), (0.55, 0.64)]),
                    rect(0.44, 0.74, 0.47, 0.84),
                    rect(0.53, 0.74, 0.56, 0.84),
                )


            def write(path, shape):
                header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, S, S, 32, 0x28)
                rows = bytearray()
                for py in range(S):
                    for px in range(S):
                        hits = 0
                        for sy in range(SS):
                            for sx in range(SS):
                                x = (px + (sx + 0.5) / SS) / S
                                y = (py + (sy + 0.5) / SS) / S
                                if shape(x, y):
                                    hits += 1
                        rows += bytes((255, 255, 255, round(255 * hits / (SS * SS))))
                with open(path, "wb") as f:
                    f.write(header + rows)


            def write_glow(path):
                header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, S, S, 32, 0x28)
                rows = bytearray()
                c = S / 2
                for py in range(S):
                    for px in range(S):
                        d = math.hypot(px + 0.5 - c, py + 0.5 - c) / c
                        rows += bytes((255, 255, 255, round(255 * max(0.0, 1.0 - d) ** 2)))
                with open(path, "wb") as f:
                    f.write(header + rows)


            out = sys.argv[1]
            write_glow(f"{out}/NPGlow.tga")
            for name, shape in [
                ("DMSettings", cog()),
                ("DMSegment", sheet()),
                ("DMReset", reset()),
                ("DMOpen", plus(0.1)),
                ("DMClose", cross()),
                ("DMLocked", lock(False)),
                ("DMUnlocked", lock(True)),
                ("DMResize", grip()),
                ("DMWidth", width_arrows()),
                ("DMArrow", chevron()),
                ("DMDamage", sword()),
                ("DMHealing", plus(0.22)),
                ("DMTaken", shield()),
                ("DMAvoidable", warning()),
                ("DMEnemyTaken", crosshair()),
                ("DMInterrupt", forbidden()),
                ("DMDispel", sparkle()),
                ("DMDeaths", skull()),
            ]:
                write(f"{out}/{name}.tga", shape)
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
                  pkgs.vorbis-tools
                ];
              }
              ''
                mkdir -p $out/Textures $out/Sounds

                python3 ${statusbarTextures} $out/Textures
                python3 ${glyphIcons} $out/Textures

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
            done < <(grep -oE '"(Textures|Sounds)\\\\[^"]+"' "$out/MerrinxUI/Util/Media.lua" | tr -d '"')
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
