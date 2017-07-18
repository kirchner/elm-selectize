#!/bin/bash

elm-live demo/Demo.elm \
    --dir=gh-pages \
    --output=gh-pages/elm.js \
    --before-build=./before-build.sh \
    --warn

