{ pkgs ? (import <nixpkgs> {}) }:

let

  elm-make = pkgs.elmPackages.elm-make;
  elm-package = pkgs.elmPackages.elm-package;
  elm-repl = pkgs.elmPackages.elm-repl;

  nodePackages = (import node-packages/composition-v6.nix {});
  elm-live = nodePackages.elm-live;

in

pkgs.stdenv.mkDerivation {

  name = "elm-env";

  buildInputs = [
    elm-make elm-package elm-repl elm-live
  ];

  shellHook = ''
    cd tests
    elm-package install
    elm-live TestRunner.elm
  '';

}
