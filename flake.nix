{
  description = "MerrinxUI - World of Warcraft: Forever addon suite";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
        { system, ... }:
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
        in
        {
          formatter = pkgs.nixfmt;

          checks = {
            inherit pre-commit-check;
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
