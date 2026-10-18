{
  description = "Overwitch: JACK client for Elektron Overbridge 2 devices";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      overlays.default = final: _prev: {
        overwitch = final.callPackage ./nix/package.nix { };
        overwitch-headless = final.callPackage ./nix/package.nix { withGui = false; };
        overwitch-udev = final.callPackage ./nix/udev.nix { };
      };

      packages = forAllSystems (
        pkgs:
        let
          ow = self.overlays.default pkgs pkgs;
        in
        ow // { default = ow.overwitch; }
      );

      nixosModules = {
        overwitch = ./nix/module.nix;
        default = self.nixosModules.overwitch;
      };

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.overwitch ];
          packages = with pkgs; [
            gdb
            indent
            valgrind
          ];
        };
      });

      checks = forAllSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        self.packages.${system}
        // {
          nixos-headless = pkgs.testers.runNixOSTest ./nix/tests/headless.nix;
          nixos-gui = pkgs.testers.runNixOSTest ./nix/tests/gui.nix;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
