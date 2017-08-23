{ pkgs ? (import <nixpkgs> {}) }:

let

  elm-make = pkgs.elmPackages.elm-make;
  elm-package = pkgs.elmPackages.elm-package;
  elm-repl = pkgs.elmPackages.elm-repl;

  nodePackages = (import node-packages/composition-v6.nix {});
  elm-live = nodePackages.elm-live;

  beforeBuild = pkgs.writeScript "before-build.sh" ''
    #! ${pkgs.bash}/bin/bash
    
    mkdir -p ./gh-pages
    ${pkgs.sass}/bin/sass static/selectize.scss > gh-pages/selectize.css
    cp static/index.html gh-pages/index.html
  '';

in

pkgs.stdenv.mkDerivation {

  name = "elm-env";

  buildInputs = [
    elm-make elm-package elm-repl elm-live beforeBuild
  ];

  shellHook = ''
    elm-package install
    elm-live demo/Demo.elm \
        --dir=gh-pages \
        --output=gh-pages/elm.js \
        --before-build=${beforeBuild} \
        --warn
  '';
}
