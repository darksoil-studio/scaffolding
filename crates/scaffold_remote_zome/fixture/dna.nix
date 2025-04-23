{ inputs, ... }:

{
  perSystem = { inputs', self', lib, system, ... }: {
    packages.forum =
      inputs.holochain-nix-builders.outputs.builders.${system}.dna {
        dnaManifest = ./dna.yaml;
        zomes = { };
      };
  };
}

