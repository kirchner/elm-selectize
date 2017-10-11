module Internal.ZipList
    exposing
        ( Direction(..)
        , EntryWithHeight
        , ZipList
        , currentEntry
        , currentHeight
        , first
        , fromList
        , fromListWithFilter
        , moveForwardTo
        , next
        , previous
        , removeCurrentEntry
        , view
        , viewList
        )

import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Internal.Entry exposing (..)


type alias ZipList a =
    { front : List (EntryWithHeight a)
    , current : EntryWithHeight a
    , back : List (EntryWithHeight a)
    , currentTop : Float
    }


type alias EntryWithHeight a =
    ( Entry a, Float )


removeCurrentEntry : ZipList a -> Maybe (ZipList a)
removeCurrentEntry ({ front, current, back, currentTop } as zipList) =
    if back |> containsActualEntries then
        case back of
            [] ->
                Nothing

            next :: rest ->
                { zipList
                    | current = next
                    , back = rest
                }
                    |> first
    else if front |> containsActualEntries then
        case front of
            [] ->
                Nothing

            previous :: rest ->
                let
                    ( _, height ) =
                        previous
                in
                { zipList
                    | front = rest
                    , current = previous
                    , currentTop = currentTop - height
                }
                    |> reverseFirst
    else
        Nothing


containsActualEntries : List (EntryWithHeight a) -> Bool
containsActualEntries entries =
    let
        isActualEntry entry =
            case entry of
                ( Entry _, _ ) ->
                    True

                _ ->
                    False
    in
    entries |> List.any isActualEntry


currentEntry : { r | current : EntryWithHeight a } -> a
currentEntry { current } =
    case current of
        ( Entry a, _ ) ->
            a

        _ ->
            Debug.crash "this should be impossible"


currentHeight : { r | current : EntryWithHeight a } -> Float
currentHeight { current } =
    current |> Tuple.second


fromList : List (Entry a) -> List Float -> Maybe (ZipList a)
fromList entries entryHeights =
    case ( entries, entryHeights ) of
        ( firstEntry :: restEntries, firstHeight :: restHeights ) ->
            { front = []
            , current = ( firstEntry, firstHeight )
            , back = zip restEntries restHeights
            , currentTop = 0
            }
                |> first

        _ ->
            Nothing


fromListWithFilter :
    (String -> a -> Bool)
    -> String
    -> List (Entry a)
    -> List Float
    -> Maybe (ZipList a)
fromListWithFilter matches query entries entryHeights =
    let
        filtered =
            zip entries entryHeights
                |> List.filterMap
                    (\( entry, height ) ->
                        case entry of
                            Entry a ->
                                if a |> matches query then
                                    Just ( Entry a, height )
                                else
                                    Nothing

                            Divider text ->
                                Just ( Divider text, height )
                    )
    in
    case filtered of
        f :: rest ->
            { front = []
            , current = f
            , back = rest
            , currentTop = 0
            }
                |> first

        _ ->
            Nothing


first : ZipList a -> Maybe (ZipList a)
first ({ front, current, back, currentTop } as zipList) =
    case current of
        ( Divider _, _ ) ->
            case back of
                [] ->
                    Nothing

                next :: rest ->
                    { front = current :: front
                    , current = next
                    , back = rest
                    , currentTop = currentTop + Tuple.second current
                    }
                        |> first

        _ ->
            Just zipList


reverseFirst : ZipList a -> Maybe (ZipList a)
reverseFirst ({ front, current, back, currentTop } as zipList) =
    case current of
        ( Divider _, _ ) ->
            case front of
                [] ->
                    Nothing

                previous :: rest ->
                    { front = rest
                    , current = previous
                    , back = current :: back
                    , currentTop = currentTop - Tuple.second previous
                    }
                        |> reverseFirst

        _ ->
            Just zipList


next : ZipList a -> ZipList a
next ({ front, current, back, currentTop } as zipList) =
    case back of
        [] ->
            zipList

        next :: rest ->
            { front = current :: front
            , current = next
            , back = rest
            , currentTop = currentTop + Tuple.second current
            }
                |> first
                |> Maybe.withDefault zipList


previous : ZipList a -> ZipList a
previous ({ front, current, back, currentTop } as zipList) =
    case front of
        [] ->
            zipList

        previous :: rest ->
            { front = rest
            , current = previous
            , back = current :: back
            , currentTop = currentTop - Tuple.second previous
            }
                |> reverseFirst
                |> Maybe.withDefault zipList


moveForwardTo : a -> ZipList a -> ZipList a
moveForwardTo a zipList =
    moveForwardToHelper a zipList
        |> Maybe.withDefault zipList


moveForwardToHelper :
    a
    -> ZipList a
    -> Maybe (ZipList a)
moveForwardToHelper a zipList =
    if (zipList.current |> Tuple.first) == Entry a then
        Just zipList
    else
        case zipList.back of
            [] ->
                Nothing

            _ ->
                zipList
                    |> next
                    |> moveForwardToHelper a



---- VIEW


type alias HtmlDetails msg =
    { attributes : List (Html.Attribute msg)
    , children : List (Html msg)
    }


type Direction
    = Upward
    | Downward


viewList :
    { r
        | menu : List (Html.Attribute Never)
        , ul : List (Html.Attribute Never)
        , entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    ->
        { select : a -> msg
        , setMouseFocus : Maybe a -> msg
        , preventClosing : Bool -> msg
        }
    -> String
    -> List (Entry a)
    -> Maybe a
    -> Html msg
viewList config { select, setMouseFocus, preventClosing } id entries mouseFocus =
    let
        menuAttrs =
            [ Attributes.id id
            , Events.onMouseDown (preventClosing True)
            , Events.onMouseUp (preventClosing False)
            , Attributes.style [ "position" => "absolute" ]
            ]
                ++ noOp config.menu
    in
    Html.div menuAttrs
        [ entries
            |> List.map
                (viewEntry
                    False
                    config
                    select
                    setMouseFocus
                    mouseFocus
                )
            |> Html.ul (noOp config.ul)
        ]


view :
    { r
        | menu : List (Html.Attribute Never)
        , ul : List (Html.Attribute Never)
        , entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
        , direction : Direction
    }
    ->
        { select : a -> msg
        , setMouseFocus : Maybe a -> msg
        , preventClosing : Bool -> msg
        }
    -> String
    -> ZipList a
    -> Maybe a
    -> Html msg
view config { select, setMouseFocus, preventClosing } id zipList mouseFocus =
    let
        menuAttrs =
            [ Attributes.id id
            , Events.onMouseDown (preventClosing True)
            , Events.onMouseUp (preventClosing False)
            , case config.direction of
                Downward ->
                    Attributes.style
                        [ "position" => "absolute" ]

                Upward ->
                    Attributes.style
                        [ "position" => "absolute"
                        , "bottom" => "100%"
                        ]
            ]
                ++ noOp config.menu
    in
    Html.div menuAttrs
        [ [ zipList.front
                |> viewUnfocusedEntriesWithHeight config select setMouseFocus mouseFocus
                |> List.reverse
          , [ zipList.current
                |> Tuple.first
                |> viewEntry True config select setMouseFocus mouseFocus
            ]
          , zipList.back
                |> viewUnfocusedEntriesWithHeight config select setMouseFocus mouseFocus
          ]
            |> List.concat
            |> Html.ul (noOp config.ul)
        ]


viewUnfocusedEntriesWithHeight :
    { r
        | entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> (a -> msg)
    -> (Maybe a -> msg)
    -> Maybe a
    -> List (EntryWithHeight a)
    -> List (Html msg)
viewUnfocusedEntriesWithHeight config select setMouseFocus mouseFocus front =
    let
        viewEntryWithHeight ( entry, _ ) =
            viewEntry
                False
                config
                select
                setMouseFocus
                mouseFocus
                entry
    in
    front |> List.map viewEntryWithHeight


viewEntry :
    Bool
    ->
        { r
            | entry : a -> Bool -> Bool -> HtmlDetails Never
            , divider : String -> HtmlDetails Never
        }
    -> (a -> msg)
    -> (Maybe a -> msg)
    -> Maybe a
    -> Entry a
    -> Html msg
viewEntry keyboardFocused config select setMouseFocus mouseFocus entry =
    let
        { attributes, children } =
            case entry of
                Entry entry ->
                    config.entry entry
                        (mouseFocus == Just entry)
                        keyboardFocused

                Divider title ->
                    config.divider title

        liAttrs attrs =
            attrs ++ noOp attributes
    in
    Html.li
        (liAttrs <|
            case entry of
                Entry entry ->
                    [ Events.onClick (select entry)
                    , Events.onMouseEnter (setMouseFocus (Just entry))
                    , Events.onMouseLeave (setMouseFocus Nothing)
                    ]

                _ ->
                    []
        )
        (children |> List.map mapToNoOp)



---- HELPER


(=>) : name -> value -> ( name, value )
(=>) name value =
    ( name, value )


noOp : List (Html.Attribute Never) -> List (Html.Attribute msg)
noOp attrs =
    List.map (Attributes.map never) attrs


mapToNoOp : Html Never -> Html msg
mapToNoOp =
    Html.map never


zip : List a -> List b -> List ( a, b )
zip listA listB =
    zipHelper listA listB [] |> List.reverse


zipHelper : List a -> List b -> List ( a, b ) -> List ( a, b )
zipHelper listA listB sum =
    case ( listA, listB ) of
        ( a :: restA, b :: restB ) ->
            zipHelper restA restB (( a, b ) :: sum)

        _ ->
            sum
