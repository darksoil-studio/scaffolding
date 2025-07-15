{
  inputs = {
    holonix.url = "github:holochain/holonix/main-0.5";

    nixpkgs.follows = "holonix/nixpkgs";
    rust-overlay.follows = "holonix/rust-overlay";
    crane.follows = "holonix/crane";

    holochain-nix-builders.url =
      "github:darksoil-studio/holochain-nix-builders/main-0.5";
    holochain-nix-builders.inputs.holonix.follows = "holonix";
  };

  nixConfig = {
    extra-substituters = [
      "https://holochain-ci.cachix.org"
      "https://darksoil-studio.cachix.org"
    ];
    extra-trusted-public-keys = [
      "holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8="
      "darksoil-studio.cachix.org-1:UEi+aujy44s41XL/pscLw37KEVpTEIn8N/kn7jO8rkc="
    ];
  };

  outputs = inputs@{ ... }:
    inputs.holonix.inputs.flake-parts.lib.mkFlake { inherit inputs; } rec {
      flake = {

        lib = rec {
          # TODO: remove this when scaffolding is fixed again
          wrapCustomTemplate = { system, pkgs, customTemplatePath }:
            let scaffolding = inputs.holonix.packages.${system}.hc-scaffold;
            in pkgs.runCommand "hc-scaffold" {
              buildInputs = [ pkgs.makeWrapper ];
              src = customTemplatePath;
            } ''
                mkdir $out
                mkdir $out/bin
                # We create the bin folder ourselves and link every binary in it
                ln -s ${scaffolding}/bin/* $out/bin
                # Except the hello binary
                rm $out/bin/hc-scaffold
                cp $src -R $out/template
                # Because we create this ourself, by creating a wrapper
                makeWrapper ${scaffolding}/bin/hc-scaffold $out/bin/hc-scaffold \
                  --add-flags "--template $out/template"
              	'';
          filterPnpmSources = { lib }:
            orig_path: type:
            let
              path = (toString orig_path);
              base = baseNameOf path;

              matchesSuffix = lib.any (suffix: lib.hasSuffix suffix base) [
                ".ts"
                ".js"
                ".json"
                ".yaml"
                ".html"
              ];
            in type == "directory" || matchesSuffix;
          cleanPnpmDepsSource = { lib }:
            src:
            lib.cleanSourceWith {
              src = lib.cleanSource src;
              filter = filterPnpmSources { inherit lib; };

              name = "pnpm-workspace";
            };
          filterScaffoldingSources = { lib }:
            orig_path: type:
            let
              path = (toString orig_path);
              base = baseNameOf path;
              parentDir = baseNameOf (dirOf path);

              matchesSuffix = lib.any (suffix: lib.hasSuffix suffix base) [
                # Keep rust sources
                ".rs"
                # Keep all toml files as they are commonly used to configure other
                # cargo-based tools
                ".toml"
                # Keep templates
                ".hbs"
              ];

              # Cargo.toml already captured above
              isCargoFile = base == "Cargo.lock";

              # .cargo/config.toml already captured above
              isCargoConfig = parentDir == ".cargo" && base == "config";
            in type == "directory" || matchesSuffix || isCargoFile
            || isCargoConfig;
          cleanScaffoldingSource = { lib }:
            src:
            lib.cleanSourceWith {
              src = lib.cleanSource src;
              filter = filterScaffoldingSources { inherit lib; };

              name = "scaffolding-workspace";
            };
        };
      };

      imports = [
        ./crates/scaffold_remote_zome/default.nix
        ./crates/sync_npm_rev_dependencies_with_nix/default.nix
        ./crates/scaffold_zome_module/default.nix
      ];

      systems = builtins.attrNames inputs.holonix.devShells;

      perSystem = { inputs', self', config, pkgs, system, lib, ... }: rec {
        devShells.default = pkgs.mkShell {
          inputsFrom = [
            inputs'.holochain-nix-builders.devShells.holochainDev
            inputs'.holonix.devShells.default
            devShells.synchronized-pnpm
          ];
        };
        packages.synchronized-pnpm = let
          pnpm-sync-npm-rev-dependencies-with-nix = pkgs.symlinkJoin {
            name = "pnpm-sync-npm-rev-dependencies-with-nix";
            paths = [ self'.packages.sync-npm-rev-dependencies-with-nix ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/sync-npm-rev-dependencies-with-nix --add-flags "--package-manager pnpm"
            '';
          };
        in pkgs.symlinkJoin {
          name = "synchronized-pnpm";
          paths = [ pkgs.pnpm ];
          buildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/pnpm --run "${pnpm-sync-npm-rev-dependencies-with-nix}/bin/sync-npm-rev-dependencies-with-nix"
          '';
        };

        devShells.synchronized-npm-rev-dependencies-with-nix = pkgs.mkShell {
          packages = [
            self'.packages.sync-npm-rev-dependencies-with-nix
            packages.npm-rev-version
          ];

          shellHook = ''
            sync-npm-rev-dependencies-with-nix
          '';
        };

        devShells.synchronized-pnpm = pkgs.mkShell {
          packages = [
            packages.synchronized-pnpm
            self'.packages.sync-npm-rev-dependencies-with-nix
            packages.npm-rev-version
          ];

          shellHook = ''
            sync-npm-rev-dependencies-with-nix --package-manager pnpm
          '';
        };

        packages.hc-scaffold-happ = let
          hcScaffold = flake.lib.wrapCustomTemplate {
            inherit pkgs system;
            customTemplatePath = ./templates/app;
          };
        in pkgs.writeShellScriptBin "hc-scaffold" ''
          if [[ "$@" == *"web-app"* ]]; then
            ${hcScaffold}/bin/hc-scaffold "$@" --setup-nix -F  
          elif [[ "$@" == *"zome"* ]]; then
            ${hcScaffold}/bin/hc-scaffold "$@"
            git add Cargo.lock
          else
            ${hcScaffold}/bin/hc-scaffold "$@"
          fi
        '';

        packages.hc-scaffold-zome = flake.lib.wrapCustomTemplate {
          inherit pkgs system;
          customTemplatePath = ./templates/zome;
        };

        packages.npm-rev-version =
          (pkgs.writeShellScriptBin "npm-rev-version" ''
            commit=$(${pkgs.git}/bin/git rev-parse HEAD)
            version=$(cat $1 | ${pkgs.jq}/bin/jq '.version' -r)
            new_version=$version-rev.$commit
            ${pkgs.nodejs_20}/bin/npm version $new_version
          '');
      };
    };
}
