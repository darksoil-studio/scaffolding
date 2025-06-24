{ inputs, ... }:

{
  perSystem = { inputs', pkgs, system, self', lib, ... }: {

    packages.scaffold-remote-zome = let
      craneLib = inputs.crane.mkLib pkgs;

      cratePath = ./.;

      cargoToml =
        builtins.fromTOML (builtins.readFile "${cratePath}/Cargo.toml");
      crate = cargoToml.package.name;

      commonArgs = {
        src = craneLib.cleanCargoSource (craneLib.path ../../.);
        doCheck = false;
        buildInputs =
          inputs.holochain-nix-builders.dependencies.${system}.holochain.buildInputs
          ++ [ pkgs.openssl ];
        nativeBuildInputs = [ pkgs.pkg-config ];
        LIBCLANG_PATH = "${pkgs.llvmPackages_18.libclang.lib}/lib";
      };
      cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
        pname = crate;
        version = "0.5.x";
      });
    in craneLib.buildPackage (commonArgs // {
      pname = crate;
      version = cargoToml.package.version;
      inherit cargoArtifacts;
    });
  };
}
