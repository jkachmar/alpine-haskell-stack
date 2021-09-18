{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    buildah
    skopeo

    # Misc. other dependencies.
    nixpkgs-fmt
    shellcheck
  ];
}
