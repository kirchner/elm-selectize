module Tests exposing (..)

import Expect
import Fuzz exposing (Fuzzer)
import Selectize.Selectize exposing (..)
import Random
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
                (List.repeat count (divider "divider")
                    ++ (trees1 |> List.map entry)
                )
                    |> first
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
                            ++ [ entry currentEntry ]
                            ++ List.repeat count (divider "divider")
                            ++ [ entry nextEntry ]
                            ++ (trees2 |> List.map entry)

                    currentEntry =
                        treeA

                    nextEntry =
                        treeB
                in
                currentEntry
                    |> next entries
                    |> Expect.equal nextEntry
        ]


testPrevious : Test
testPrevious =
    describe "previous"
        [ fuzz (Fuzz.intRange 0 42) "select the previous non divider" <|
            \count ->
                let
                    entries =
                        (trees1 |> List.map entry)
                            ++ [ entry previousEntry ]
                            ++ List.repeat count (divider "divider")
                            ++ [ entry currentEntry ]
                            ++ (trees2 |> List.map entry)

                    currentEntry =
                        treeA

                    previousEntry =
                        treeB
                in
                currentEntry
                    |> previous entries Nothing
                    |> Expect.equal previousEntry
        ]


testTopAndHeight : Test
testTopAndHeight =
    describe "topAndHeight"
        [ fuzz3 (listCount (Fuzz.intRange 0 42) (List.length trees1))
            (Fuzz.intRange 0 200)
            (Fuzz.intRange 0 1000)
            "satisfies a priori bounds"
          <|
            \entryHeights menuHeight scrollTop ->
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
                List.head trees1
                    |> topAndHeight entryHeights menuHeight scrollTop entries
                    |> Expect.all
                        [ Tuple.first >> Expect.atLeast 0
                        , Tuple.first >> Expect.atMost sum
                        , Tuple.second >> Expect.atLeast 0
                        , Tuple.second >> Expect.atMost maximum
                        , Tuple.second >> Expect.atLeast minimum
                        ]
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
