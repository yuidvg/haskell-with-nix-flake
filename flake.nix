{
  description = "<project-name> - <project-description>";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    haskell-flake.url = "github:srid/haskell-flake";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
      ];
      imports = [
        inputs.haskell-flake.flakeModule
      ];
      perSystem =
        {
          self',
          system,
          lib,
          config,
          pkgs,
          ...
        }:
        let
          # Helper function to create test derivations
          mkTestScript = name: script: deps: pkgs.stdenv.mkDerivation {
            inherit name;
            src = ./.;
            nativeBuildInputs = deps ++ [ pkgs.bash ];
            buildPhase = ''
              # Make script executable and run test
              chmod +x ${script}
              ./${script} $PWD/test/key.hex
            '';
            installPhase = ''
              mkdir -p $out
              echo "${name} completed successfully" > $out/result
            '';
          };
        in
        {

          haskellProjects.default = {
            # basePackages = pkgs.haskellPackages;

            # Packages to add on top of `basePackages`, e.g. from Hackage
            #packages = {
            #  aeson.source = "1.5.0.0"; # Hackage version
            #};

            # my-haskell-package development shell configuration
            #devShell = {
            #  hlsCheck.enable = false;
            #};

            # What should haskell-flake add to flake outputs?
            autoWire = [
              "packages"
              "apps"
              "checks"
            ]; # Wire all but the devShell
          };

          # Set the default package to be the <project-name> executable
          packages.default = self'.packages.<project-name>;

          # E2E test that compares <project-name> output with oathtool
          checks.e2e-test = mkTestScript
            "<project-name>-e2e-test"
            "test/e2e-test.sh"
            [ self'.packages.<project-name> pkgs.oathToolkit pkgs.openssl ];

          devShells.default = pkgs.mkShell {
            name = "<project-name> development shell";
            inputsFrom = [
              config.haskellProjects.default.outputs.devShell
            ];
            nativeBuildInputs = with pkgs; [
              # other development tools.
              haskellPackages.cabal-gild
              haskellPackages.ghci-dap
              haskellPackages.haskell-debug-adapter
              haskellPackages.haskell-dap
              oathToolkit
            ];
          };
        };
    };
}
