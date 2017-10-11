module Internal.ZipList
    exposing
        ( Direction(..)
        , EntryWithHeight
        , Msg
        , State
        , ZipList
        , currentEntry
        , currentHeight
        , decodeMeasurements
        , filter
        , first
        , fromList
        , fromListWithFilter
        , init
        , keyboardFocus
        , moveForwardTo
        , next
        , onKeydown
        , previous
        , removeCurrentEntry
        , update
        , view
        , viewList
        )

import DOM
import Dom.Scroll
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Internal.Entry exposing (..)
import Json.Decode as Decode exposing (Decoder)
import Keyboard.Extra
    exposing
        ( Key
            ( ArrowDown
            , ArrowUp
            , BackSpace
            , Delete
            , Enter
            , Escape
            )
        , fromCode
        )
import Task


---- MODEL


type alias State a =
    { id : String
    , entries : List (Entry a)
    , zipList : Maybe (ZipList a)
    , mouseFocus : Maybe a

    -- dom measurements
    , entryHeights : List Float
    , menuHeight : Float
    , scrollTop : Float
    }


init : String -> List (Entry a) -> State a
init id entries =
    { id = id
    , entries = entries
    , zipList = Nothing
    , mouseFocus = Nothing
    , entryHeights = []
    , menuHeight = 0
    , scrollTop = 0
    }


filter : (a -> Bool) -> State a -> ( State a, Cmd (Msg a) )
filter matches state =
    ( { state
        | zipList =
            fromListWithFilter matches state.entries state.entryHeights
        , mouseFocus = Nothing
      }
    , scroll state.id 0
    )


keyboardFocus : State a -> Maybe a
keyboardFocus state =
    state.zipList
        |> Maybe.map currentEntry


type alias Heights =
    { entries : List Float
    , menu : Float
    }



---- UPDATE


type Msg a
    = NoOp
    | SetMeasurments Heights Float Bool
    | SetMouseFocus (Maybe a)
    | SetKeyboardFocus Movement Float
    | PreventClosing Bool
    | Select a


type Movement
    = Up
    | Down
    | PageUp
    | PageDown


update :
    { select : a -> msg
    , preventClosing : Bool -> msg
    , openMenu : msg
    }
    -> Maybe a
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update { select, preventClosing, openMenu } selection state msg =
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        SetMeasurments heights scrollTop openM ->
            let
                newZipList =
                    fromList state.entries heights.entries
                        |> Maybe.map
                            (case selection of
                                Just a ->
                                    moveForwardTo a

                                Nothing ->
                                    identity
                            )

                top =
                    newZipList
                        |> Maybe.map .currentTop
                        |> Maybe.withDefault 0

                height =
                    newZipList
                        |> Maybe.map currentHeight
                        |> Maybe.withDefault 0
            in
            ( { state
                | zipList = newZipList
                , entryHeights = heights.entries
                , menuHeight = heights.menu
                , scrollTop = scrollTop
              }
            , scroll state.id (top - (heights.menu - height) / 2)
            , if openM then
                Just openMenu
              else
                Nothing
            )

        SetMouseFocus focus ->
            ( { state | mouseFocus = focus }
            , Cmd.none
            , Nothing
            )

        SetKeyboardFocus movement scrollTop ->
            let
                newZipList =
                    case movement of
                        Up ->
                            state.zipList
                                |> Maybe.map previous

                        Down ->
                            state.zipList
                                |> Maybe.map next

                        _ ->
                            state.zipList

                newState =
                    { state | zipList = newZipList }
            in
            case newZipList of
                Just zipList ->
                    let
                        top =
                            zipList.currentTop

                        height =
                            currentHeight zipList

                        y =
                            if top < scrollTop then
                                top
                            else if
                                (top + height)
                                    > (scrollTop + state.menuHeight)
                            then
                                top + height - state.menuHeight
                            else
                                scrollTop
                    in
                    ( newState
                    , scroll state.id y
                    , Nothing
                    )

                Nothing ->
                    ( newState
                    , Cmd.none
                    , Nothing
                    )

        PreventClosing bool ->
            ( state
            , Cmd.none
            , Just (preventClosing bool)
            )

        Select a ->
            ( state
            , Cmd.none
            , Just (select a)
            )



---- CMDS


scroll : String -> Float -> Cmd (Msg a)
scroll id y =
    Task.attempt (\_ -> NoOp) <|
        Dom.Scroll.toY id y



---- EVENTS


onKeydown :
    (Decoder Float -> Decoder Float)
    -> (Msg a -> msg)
    -> (Int -> Maybe msg)
    -> Html.Attribute msg
onKeydown path lift onKey =
    Decode.map2
        (\code scrollTop ->
            case code |> fromCode of
                ArrowUp ->
                    Ok (lift (SetKeyboardFocus Up scrollTop))

                ArrowDown ->
                    Ok (lift (SetKeyboardFocus Down scrollTop))

                _ ->
                    case onKey code of
                        Just msg ->
                            Ok msg

                        Nothing ->
                            Err "not handling that key here"
        )
        Events.keyCode
        (scrollTopDecoder
            |> DOM.childNode 0
            |> path
            |> DOM.target
        )
        |> Decode.andThen fromResult
        |> Events.onWithOptions "keydown"
            { preventDefault = True
            , stopPropagation = False
            }


decodeMeasurements : (Decoder (Msg a) -> Decoder (Msg a)) -> Bool -> Decoder (Msg a)
decodeMeasurements path openMenu =
    Decode.map3
        (\entryHeights menuHeight scrollTop ->
            SetMeasurments { entries = entryHeights, menu = menuHeight } scrollTop openMenu
        )
        entryHeightsDecoder
        menuHeightDecoder
        scrollTopDecoder
        |> DOM.childNode 0
        |> path
        |> DOM.target


entryHeightsDecoder : Decoder (List Float)
entryHeightsDecoder =
    Decode.field "offsetHeight" Decode.float
        |> DOM.childNodes
        |> DOM.childNode 0


menuHeightDecoder : Decoder Float
menuHeightDecoder =
    Decode.field "clientHeight" Decode.float


scrollTopDecoder : Decoder Float
scrollTopDecoder =
    Decode.field "scrollTop" Decode.float


fromResult : Result String a -> Decoder a
fromResult result =
    case result of
        Ok val ->
            Decode.succeed val

        Err reason ->
            Decode.fail reason



---- VIEW


type alias ViewConfig a =
    { menu : List (Html.Attribute Never)
    , ul : List (Html.Attribute Never)
    , entry : a -> Bool -> Bool -> HtmlDetails Never
    , divider : String -> HtmlDetails Never
    , direction : Direction
    }


type alias HtmlDetails msg =
    { attributes : List (Html.Attribute msg)
    , children : List (Html msg)
    }


type Direction
    = Upward
    | Downward


view :
    ViewConfig a
    -> State a
    -> Html (Msg a)
view config state =
    let
        menuAttrs =
            [ Attributes.id state.id
            , Events.onMouseDown (PreventClosing True)
            , Events.onMouseUp (PreventClosing False)
            , Attributes.style [ "position" => "absolute" ]
            ]
                ++ noOp config.menu
    in
    case state.zipList of
        Nothing ->
            Html.text ""

        Just zipList ->
            Html.div
                [ Attributes.style
                    [ "position" => "relative" ]
                ]
                [ viewZipList
                    config
                    { select = Select
                    , setMouseFocus = SetMouseFocus
                    , preventClosing = PreventClosing
                    }
                    state.id
                    zipList
                    state.mouseFocus
                ]


viewList :
    { r
        | menu : List (Html.Attribute Never)
        , ul : List (Html.Attribute Never)
        , entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> State a
    -> Html Never
viewList config state =
    let
        menuAttrs =
            [ Attributes.style [ "position" => "absolute" ] ]
                ++ noOp config.menu
    in
    Html.div
        [ Attributes.style
            [ "overflow" => "hidden"
            , "position" => "relative"
            ]
        ]
        [ Html.div menuAttrs
            [ state.entries
                |> List.map
                    (viewEntry
                        False
                        config
                        Nothing
                        state.mouseFocus
                    )
                |> Html.ul (noOp config.ul)
            ]
        ]


viewZipList :
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
viewZipList config { select, setMouseFocus, preventClosing } id zipList mouseFocus =
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
                |> viewEntry True
                    config
                    (Just
                        { select = select
                        , setMouseFocus = setMouseFocus
                        }
                    )
                    mouseFocus
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
                (Just
                    { select = select
                    , setMouseFocus = setMouseFocus
                    }
                )
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
    ->
        Maybe
            { select : a -> msg
            , setMouseFocus : Maybe a -> msg
            }
    -> Maybe a
    -> Entry a
    -> Html msg
viewEntry keyboardFocused config tagger mouseFocus entry =
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
                    case tagger of
                        Just { select, setMouseFocus } ->
                            [ Events.onClick (select entry)
                            , Events.onMouseEnter (setMouseFocus (Just entry))
                            , Events.onMouseLeave (setMouseFocus Nothing)
                            ]

                        Nothing ->
                            []

                _ ->
                    []
        )
        (children |> List.map mapToNoOp)



---- ZIPLIST


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
    (a -> Bool)
    -> List (Entry a)
    -> List Float
    -> Maybe (ZipList a)
fromListWithFilter matches entries entryHeights =
    let
        filtered =
            zip entries entryHeights
                |> List.filterMap
                    (\( entry, height ) ->
                        case entry of
                            Entry a ->
                                if a |> matches then
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
