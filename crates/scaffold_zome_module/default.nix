{ inputs, self, ... }:

{
  perSystem = { inputs', self', pkgs, system, lib, ... }: {

    packages.scaffold-zome-module = let
      craneLib = inputs.crane.mkLib pkgs;

      cratePath = ./.;

      cargoToml =
        builtins.fromTOML (builtins.readFile "${cratePath}/Cargo.toml");
      crate = (lib.elemAt cargoToml.bin 0).name;

      commonArgs = {
        src = (self.lib.cleanScaffoldingSource { inherit lib; })
          (craneLib.path ../../.);
        doCheck = false;
        buildInputs =
          inputs.holochain-nix-builders.dependencies.${system}.holochain.buildInputs;
        cargoExtraArgs = "--locked --package scaffold_zome_module";
      };
    in craneLib.buildPackage (commonArgs // {
      pname = crate;
      version = cargoToml.package.version;
    });

  };
}
