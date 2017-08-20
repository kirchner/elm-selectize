module Tests exposing (..)

import Expect
import Fuzz exposing (Fuzzer)
import Random
import Selectize.Selectize exposing (..)
import Test exposing (..)


testFilter : Test
testFilter =
    let
        toLabel =
            identity

        entriesIn =
            List.map entry
                [ "foobar"
                , "bar"
                , "foofoo"
                ]

        entriesOut =
            List.map entry
                [ "foobar"
                , "foofoo"
                ]
    in
    describe "filter"
        [ test "empty query returns orginal list" <|
            \_ ->
                entriesIn
                    |> filter toLabel ""
                    |> Expect.equal entriesIn
        , test "return matching entries" <|
            \_ ->
                entriesIn
                    |> filter toLabel "foo"
                    |> Expect.equal entriesOut
        , test "no matching entires" <|
            \_ ->
                entriesIn
                    |> filter toLabel "not matching"
                    |> Expect.equal []
        ]


testFirst : Test
testFirst =
    describe "first"
        [ fuzz (Fuzz.intRange 0 42) "first entries are dividers" <|
            \count ->
                let
                    entries =
                        List.repeat count (divider "divider")
                            ++ (trees1 |> List.map entry)

                    heights =
                        List.repeat (List.length entries) 30
                in
                fromList entries heights
                    |> Maybe.map currentEntry
                    |> Expect.equal (List.head trees1)
        ]


testNext : Test
testNext =
    describe "next"
        [ fuzz (Fuzz.intRange 0 42) "select the next non divider" <|
            \count ->
                let
                    entries =
                        (trees1 |> List.map entry)
                            ++ [ entry current ]
                            ++ List.repeat count (divider "divider")
                            ++ [ entry next ]
                            ++ (trees2 |> List.map entry)

                    heights =
                        List.repeat (List.length entries) 30

                    current =
                        treeA

                    next =
                        treeB
                in
                fromList entries heights
                    |> Maybe.map (moveForwardTo current)
                    |> Maybe.map zipNext
                    |> Maybe.map currentEntry
                    |> Expect.equal (Just next)
        ]


testPrevious : Test
testPrevious =
    describe "previous"
        [ fuzz (Fuzz.intRange 0 42) "select the previous non divider" <|
            \count ->
                let
                    entries =
                        (trees1 |> List.map entry)
                            ++ [ entry previous ]
                            ++ List.repeat count (divider "divider")
                            ++ [ entry current ]
                            ++ (trees2 |> List.map entry)

                    heights =
                        List.repeat (List.length entries) 30

                    current =
                        treeA

                    previous =
                        treeB
                in
                fromList entries heights
                    |> Maybe.map (moveForwardTo current)
                    |> Maybe.map zipPrevious
                    |> Maybe.map currentEntry
                    |> Expect.equal (Just previous)
        ]


testTopAndHeight : Test
testTopAndHeight =
    describe "topAndHeight"
        [ fuzz (listCount (Fuzz.intRange 0 42) (List.length trees1))
            "satisfies a priori bounds"
          <|
            \entryHeights ->
                let
                    entries =
                        trees1 |> List.map entry

                    sum =
                        List.foldl (+) 0 entryHeights

                    maximum =
                        List.maximum entryHeights
                            |> Maybe.withDefault 0

                    minimum =
                        List.minimum entryHeights
                            |> Maybe.withDefault 0
                in
                case fromList entries entryHeights of
                    Just zipList ->
                        zipList
                            |> Expect.all
                                [ zipCurrentScrollTop
                                    >> Expect.all
                                        [ Expect.atLeast 0
                                        , Expect.atMost sum
                                        ]
                                , zipCurrentHeight
                                    >> Expect.all
                                        [ Expect.atLeast 0
                                        , Expect.atMost maximum
                                        , Expect.atLeast minimum
                                        ]
                                ]

                    Nothing ->
                        Expect.fail "could not create zipList"
        ]



{- fuzzer -}


listCount : Fuzzer a -> Int -> Fuzzer (List a)
listCount fuzzer count =
    if count > 1 then
        Fuzz.map2 (\a rest -> a :: rest)
            fuzzer
            (listCount fuzzer (count - 1))
    else
        fuzzer |> Fuzz.map (\a -> [ a ])



{- constants -}


treeA : String
treeA =
    "not really a tree"


treeB : String
treeB =
    "not really a tree, either"


trees1 : List String
trees1 =
    [ "Abelia x grandiflora"
    , "Abienus festuschristus"
    , "Abies alba"
    , "Acacia dealbata"
    , "Acacia retinodes"
    , "Acer buergerianum"
    ]


trees2 : List String
trees2 =
    [ "Carya cordiformis"
    , "Cascabela thevetia"
    , "Cassia siberiana"
    , "Castanea sativa"
    , "Casuarina stricta"
    , "Catalpa x erubescens"
    , "Ceanothus x delilianus"
    , "Cedrus libani"
    , "Ceiba speciosa"
    , "Celtis occidentalis"
    , "Cephalanthus occidentalis"
    ]
