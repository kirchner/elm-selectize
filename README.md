# Filterable Dropdown Menu [![Build Status](https://travis-ci.org/kirchner/elm-selectize.svg?branch=master)](https://travis-ci.org/kirchner/elm-selectize)

This is a customizable dropdown menu with the following features:

* filtering the displayed entries with a textfield
* keyboard selection using up/down arrow keys and enter/escape
* auto scrolling if the menu is styled with a maximum height and `overflow-y:
  scroll`
* you can insert non-selectable dividers between entries
* the styling and rendering of the entries can be fully customized

Check out the [demo](https://kirchner.github.io/elm-selectize) or run it
locally by executing `./elm-live.sh`


## Nix Support

If you are using [NixOS](https://nixos.org/) you run the demo locally via

```
$ nix-shell
```

You can run the test suite with

```
$ nix-shell test.nix
```
