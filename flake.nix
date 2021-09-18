{
  description = "TODO: Summary";

  inputs = { 
    # Stable Nix package set; pinned to the latest 21.05 release.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05-small";
  };

  outputs = { self, nixpkgs }: {
    devShell.x86_64-linux = import ./shell.nix {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
    };
  };
}
