module Selectize.MultiSelectize
    exposing
        ( Entry
        , Heights
        , Input
        , LEntry(..)
        , Movement(..)
        , Msg(..)
        , State
        , ViewConfig
        , ZipList
        , closed
        , contains
        , currentEntry
        , divider
        , entry
        , fromList
        , moveForwardTo
        , simple
        , update
        , view
        , viewConfig
        , zipCurrentHeight
        , zipNext
        , zipPrevious
        )

import DOM
import Dom
import Dom.Scroll
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Html.Lazy
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
    , entries : List (LEntry a)
    , query : String
    , queryWidth : Float
    , zipList : Maybe (ZipList a)
    , open : Bool
    , mouseFocus : Maybe a
    , preventBlur : Bool

    -- dom measurements
    , entryHeights : List Float
    , menuHeight : Float
    , scrollTop : Float
    }


type alias Heights =
    { entries : List Float
    , menu : Float
    }


type LEntry a
    = LEntry a String
    | LDivider String


removeLabel : LEntry a -> Entry a
removeLabel labeledEntry =
    case labeledEntry of
        LEntry a _ ->
            Entry a

        LDivider text ->
            Divider text


selectFirst : List (LEntry a) -> a -> Maybe ( a, String )
selectFirst entries a =
    case entries of
        [] ->
            Nothing

        first :: rest ->
            case first of
                LEntry value label ->
                    if a == value then
                        Just ( a, label )
                    else
                        selectFirst rest a

                _ ->
                    selectFirst rest a


closed : String -> (a -> String) -> List (Entry a) -> State a
closed id toLabel entries =
    let
        addLabel entry =
            case entry of
                Entry a ->
                    LEntry a (toLabel a)

                Divider text ->
                    LDivider text

        labeledEntries =
            entries |> List.map addLabel
    in
    { id = id
    , entries = labeledEntries
    , query = ""
    , queryWidth = 0
    , zipList = Nothing
    , open = False
    , mouseFocus = Nothing
    , preventBlur = False
    , entryHeights = []
    , menuHeight = 0
    , scrollTop = 0
    }



---- CONFIGURATION


type alias ViewConfig a =
    { container : List (Html.Attribute Never)
    , menu : List (Html.Attribute Never)
    , ul : List (Html.Attribute Never)
    , entry : a -> Bool -> Bool -> HtmlDetails Never
    , divider : String -> HtmlDetails Never
    , input : Input a
    }


type alias HtmlDetails msg =
    { attributes : List (Html.Attribute msg)
    , children : List (Html msg)
    }


type Entry a
    = Entry a
    | Divider String


entry : a -> Entry a
entry a =
    Entry a


divider : String -> Entry a
divider title =
    Divider title


viewConfig :
    { container : List (Html.Attribute Never)
    , menu : List (Html.Attribute Never)
    , ul : List (Html.Attribute Never)
    , entry : a -> Bool -> Bool -> HtmlDetails Never
    , divider : String -> HtmlDetails Never
    , input : Input a
    }
    -> ViewConfig a
viewConfig config =
    { container = config.container
    , menu = config.menu
    , ul = config.ul
    , entry = config.entry
    , divider = config.divider
    , input = config.input
    }



---- UPDATE


type Msg a
    = NoOp
      -- open/close menu
    | OpenMenu Heights Float
    | CloseMenu
    | FocusTextfield
    | BlurTextfield
    | PreventClosing Bool
      -- query
    | SetQuery String
    | SetQueryWidth Float
      -- handle focus and selection
    | SetMouseFocus (Maybe a)
    | Select a
    | SetKeyboardFocus Movement Float
    | SelectKeyboardFocusAndBlur
    | ClearSelection


type Movement
    = Up
    | Down
    | PageUp
    | PageDown


update :
    { select : a -> msg
    , unselect : a -> msg
    , clearSelection : msg
    }
    -> List a
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update { select, unselect, clearSelection } selections state msg =
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        OpenMenu heights scrollTop ->
            let
                newZipList =
                    fromList state.entries heights.entries

                top =
                    newZipList
                        |> Maybe.map .currentTop
                        |> Maybe.withDefault 0

                height =
                    newZipList
                        |> Maybe.map zipCurrentHeight
                        |> Maybe.withDefault 0
            in
            ( { state
                | zipList = newZipList
                , open = True
                , mouseFocus = Nothing
                , query = ""
                , entryHeights = heights.entries
                , menuHeight = heights.menu
                , scrollTop = scrollTop
              }
            , Cmd.batch
                [ scroll state.id (top - (heights.menu - height) / 2)
                , Task.attempt (\_ -> NoOp) <|
                    Dom.focus (multiTextfieldId state.id)
                ]
            , Nothing
            )

        CloseMenu ->
            if state.preventBlur then
                ( state, Cmd.none, Nothing )
            else
                ( state |> reset
                , Cmd.none
                , Nothing
                )

        FocusTextfield ->
            ( state
            , Cmd.none
            , Nothing
            )

        BlurTextfield ->
            ( state
            , blur state.id
            , Nothing
            )

        PreventClosing preventBlur ->
            ( { state | preventBlur = preventBlur }
            , Cmd.none
            , Nothing
            )

        SetQuery newQuery ->
            let
                newZipList =
                    fromListWithFilter newQuery state.entries state.entryHeights
            in
            ( { state
                | query = newQuery
                , zipList = newZipList
                , mouseFocus = Nothing
              }
            , scroll state.id 0
            , Nothing
            )

        SetQueryWidth newWidth ->
            ( { state | queryWidth = Debug.log "queryWidth" newWidth }
            , Cmd.none
            , Nothing
            )

        SetMouseFocus focus ->
            ( { state | mouseFocus = focus }
            , Cmd.none
            , Nothing
            )

        Select a ->
            ( state |> reset
            , Cmd.none
            , Just (select a)
            )

        SetKeyboardFocus movement scrollTop ->
            state
                |> updateKeyboardFocus movement
                |> scrollToKeyboardFocus state.id scrollTop

        SelectKeyboardFocusAndBlur ->
            ( state |> reset
            , blur state.id
            , state.zipList
                |> Maybe.map currentEntry
                |> Maybe.map select
            )

        ClearSelection ->
            ( state
            , Cmd.none
            , Just clearSelection
            )


reset : State a -> State a
reset state =
    { state
        | query = ""
        , zipList = Nothing
        , open = False
        , mouseFocus = Nothing
    }


updateKeyboardFocus :
    Movement
    -> State a
    -> ( State a, Cmd (Msg a), Maybe msg )
updateKeyboardFocus movement state =
    let
        newZipList =
            case movement of
                Up ->
                    state.zipList
                        |> Maybe.map zipPrevious

                Down ->
                    state.zipList
                        |> Maybe.map zipNext

                _ ->
                    state.zipList
    in
    ( { state
        | zipList = newZipList
      }
    , Cmd.none
    , Nothing
    )


scrollToKeyboardFocus :
    String
    -> Float
    -> ( State a, Cmd (Msg a), Maybe msg )
    -> ( State a, Cmd (Msg a), Maybe msg )
scrollToKeyboardFocus id scrollTop ( state, cmd, maybeMsg ) =
    case state.zipList of
        Just zipList ->
            let
                top =
                    zipList.currentTop

                height =
                    zipCurrentHeight zipList

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
            ( state
            , Cmd.batch [ scroll id y, cmd ]
            , maybeMsg
            )

        Nothing ->
            ( state
            , cmd
            , maybeMsg
            )



---- VIEW


view : ViewConfig a -> List a -> State a -> Html (Msg a)
view config selections state =
    let
        selectionTexts =
            selections
                |> List.filterMap (selectFirst state.entries)
                |> List.map Tuple.second

        menuAttrs =
            [ Attributes.id (menuId state.id)
            , Events.onMouseDown (PreventClosing True)
            , Events.onMouseUp (PreventClosing False)
            , Attributes.style [ "position" => "absolute" ]
            ]
                ++ noOp config.menu
    in
    case state.zipList of
        Nothing ->
            Html.div
                [ Attributes.style
                    [ "overflow" => "hidden"
                    , "position" => "relative"
                    ]
                ]
                [ config.input
                    state.id
                    selectionTexts
                    state.query
                    state.queryWidth
                    state.open
                , Html.div menuAttrs
                    [ state.entries
                        |> List.map
                            (removeLabel >> viewUnfocusedEntry config Nothing)
                        |> Html.ul (noOp config.ul)
                    ]
                ]

        Just zipList ->
            Html.div
                [ Attributes.style
                    [ "position" => "relative" ]
                ]
                [ config.input
                    state.id
                    selectionTexts
                    state.query
                    state.queryWidth
                    state.open
                , Html.div menuAttrs
                    [ [ zipList.front
                            |> viewEntries config state
                            |> List.reverse
                      , [ zipList.current
                            |> viewCurrentEntry config state
                        ]
                      , zipList.back
                            |> viewEntries config state
                      ]
                        |> List.concat
                        |> Html.ul (noOp config.ul)
                    ]
                ]


viewEntries :
    { r
        | entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> State a
    -> List (EntryWithHeight a)
    -> List (Html (Msg a))
viewEntries config state front =
    let
        viewEntry ( entry, _ ) =
            Html.Lazy.lazy3 viewUnfocusedEntry
                config
                state.mouseFocus
                entry
    in
    front |> List.map viewEntry


viewCurrentEntry :
    { r
        | entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> State a
    -> EntryWithHeight a
    -> Html (Msg a)
viewCurrentEntry config state current =
    current
        |> Tuple.first
        |> viewFocusedEntry config state.mouseFocus


viewUnfocusedEntry :
    { r
        | entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> Maybe a
    -> Entry a
    -> Html (Msg a)
viewUnfocusedEntry config mouseFocus entry =
    viewEntry config False mouseFocus entry


viewFocusedEntry :
    { r
        | entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> Maybe a
    -> Entry a
    -> Html (Msg a)
viewFocusedEntry config mouseFocus entry =
    viewEntry config True mouseFocus entry


viewEntry :
    { r
        | entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> Bool
    -> Maybe a
    -> Entry a
    -> Html (Msg a)
viewEntry config keyboardFocused mouseFocus entry =
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
                    [ Events.onClick (Select entry)
                    , Events.onMouseEnter (SetMouseFocus (Just entry))
                    , Events.onMouseLeave (SetMouseFocus Nothing)
                    ]

                _ ->
                    []
        )
        (children |> List.map mapToNoOp)


type alias Input a =
    String
    -> List String
    -> String
    -> Float
    -> Bool
    -> Html (Msg a)


simple :
    { attrs : Bool -> List (Html.Attribute Never)
    , selection : String -> Html Never
    , placeholder : Html Never
    }
    -> String
    -> List String
    -> String
    -> Float
    -> Bool
    -> Html (Msg a)
simple config id selections query queryWidth open =
    let
        selectionDivs =
            selections
                |> List.map config.selection
                |> List.map mapToNoOp
    in
    Html.div []
        [ Html.div
            ([ Events.on "click" focusDecoder ]
                ++ noOp (config.attrs open)
            )
            (Html.div
                [ Attributes.style
                    [ "width" => "0"
                    , "overflow" => "hidden"
                    ]
                ]
                [ Html.span
                    [ Attributes.class "selectize__multi-textfield-copy" ]
                    [ Html.text query ]
                ]
                :: (case selectionDivs of
                        [] ->
                            [ config.placeholder |> mapToNoOp ]

                        _ ->
                            selectionDivs
                   )
                ++ [ Html.input
                        [ Attributes.id (multiTextfieldId id)
                        , Attributes.class "selectize__multi-textfield"
                        , Attributes.style
                            [ "width" => (toString (queryWidth + 10) ++ "px") ]
                        , Events.onInput SetQuery
                        , Events.on "keyup" decodeLength
                        , Events.onBlur CloseMenu
                        ]
                        []
                   ]
            )
        ]


decodeLength =
    Decode.map
        (\width -> Ok (SetQueryWidth width))
        (Decode.field "offsetWidth" Decode.float
            |> DOM.childNode 0
            |> DOM.childNode 0
            |> DOM.parentElement
            |> DOM.target
        )
        |> Decode.andThen fromResult


multiTextfieldId : String -> String
multiTextfieldId id =
    id ++ "__multi-textfield"


buttons :
    Maybe (Html Never)
    -> Maybe (Bool -> Html Never)
    -> Bool
    -> Bool
    -> Html (Msg a)
buttons clearButton toggleButton sthSelected open =
    Html.div
        [ Attributes.style
            [ "position" => "absolute"
            , "right" => "0"
            , "top" => "0"
            , "display" => "flex"
            ]
        ]
        [ case ( clearButton, sthSelected ) of
            ( Just clear, True ) ->
                Html.div
                    [ Events.onClick ClearSelection ]
                    [ clear |> mapToNoOp ]

            _ ->
                Html.text ""
        , case toggleButton of
            Just toggle ->
                Html.div
                    [ case open of
                        True ->
                            Events.onWithOptions "click"
                                { stopPropagation = True
                                , preventDefault = False
                                }
                                (Decode.succeed BlurTextfield)

                        False ->
                            Events.onWithOptions "click"
                                { stopPropagation = True
                                , preventDefault = False
                                }
                                (Decode.succeed FocusTextfield)
                    ]
                    [ toggle open |> mapToNoOp ]

            Nothing ->
                Html.div [] []
        ]


focusDecoder : Decoder (Msg a)
focusDecoder =
    Decode.map3
        (\entryHeights menuHeight scrollTop ->
            OpenMenu { entries = entryHeights, menu = menuHeight } scrollTop
        )
        entryHeightsDecoder
        menuHeightDecoder
        scrollTopDecoder


keydownOptions : Events.Options
keydownOptions =
    { preventDefault = True
    , stopPropagation = False
    }


keydownDecoder : Decoder (Msg a)
keydownDecoder =
    Decode.map2
        (\code scrollTop ->
            case code |> fromCode of
                ArrowUp ->
                    Ok (SetKeyboardFocus Up scrollTop)

                ArrowDown ->
                    Ok (SetKeyboardFocus Down scrollTop)

                Enter ->
                    Ok SelectKeyboardFocusAndBlur

                Escape ->
                    Ok BlurTextfield

                _ ->
                    Err "not handling that key here"
        )
        Events.keyCode
        scrollTopDecoder
        |> Decode.andThen fromResult


keyupDecoder : Decoder (Msg a)
keyupDecoder =
    Events.keyCode
        |> Decode.map
            (\code ->
                case code |> fromCode of
                    BackSpace ->
                        Ok ClearSelection

                    Delete ->
                        Ok ClearSelection

                    _ ->
                        Err "not handling that key here"
            )
        |> Decode.andThen fromResult



---- HELPER


contains : String -> String -> Bool
contains query label =
    label
        |> String.toLower
        |> String.contains (String.toLower query)


(=>) : name -> value -> ( name, value )
(=>) name value =
    ( name, value )



---- VIEW HELPER


menuId : String -> String
menuId id =
    id ++ "__menu"


textfieldId : String -> String
textfieldId id =
    id ++ "__textfield"


noOp : List (Html.Attribute Never) -> List (Html.Attribute (Msg a))
noOp attrs =
    List.map (Attributes.map (\_ -> NoOp)) attrs


mapToNoOp : Html Never -> Html (Msg a)
mapToNoOp =
    Html.map (\_ -> NoOp)



---- CMDS


scroll : String -> Float -> Cmd (Msg a)
scroll id y =
    Task.attempt (\_ -> NoOp) <|
        Dom.Scroll.toY (menuId id) y


focus : String -> Cmd (Msg a)
focus id =
    Task.attempt (\_ -> NoOp) <|
        Dom.focus (textfieldId id)


blur : String -> Cmd (Msg a)
blur id =
    Task.attempt (\_ -> NoOp) <|
        Dom.blur (textfieldId id)



---- DECODER


entryHeightsDecoder : Decoder (List Float)
entryHeightsDecoder =
    Decode.field "offsetHeight" Decode.float
        |> DOM.childNodes
        |> DOM.childNode 0
        |> DOM.childNode 1
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.target


menuHeightDecoder : Decoder Float
menuHeightDecoder =
    DOM.childNode 1 (Decode.field "clientHeight" Decode.float)
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.target


scrollTopDecoder : Decoder Float
scrollTopDecoder =
    DOM.childNode 1 (Decode.field "scrollTop" Decode.float)
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.target


fromResult : Result String a -> Decoder a
fromResult result =
    case result of
        Ok val ->
            Decode.succeed val

        Err reason ->
            Decode.fail reason



---- ZIPLIST


type alias ZipList a =
    { front : List (EntryWithHeight a)
    , current : EntryWithHeight a
    , back : List (EntryWithHeight a)
    , currentTop : Float
    }


type alias EntryWithHeight a =
    ( Entry a, Float )


currentEntry : { r | current : EntryWithHeight a } -> a
currentEntry { current } =
    case current of
        ( Entry a, _ ) ->
            a

        _ ->
            Debug.crash "this should be impossible"


zipCurrentHeight : { r | current : EntryWithHeight a } -> Float
zipCurrentHeight { current } =
    current |> Tuple.second


fromList : List (LEntry a) -> List Float -> Maybe (ZipList a)
fromList entries entryHeights =
    case ( entries |> List.map removeLabel, entryHeights ) of
        ( firstEntry :: restEntries, firstHeight :: restHeights ) ->
            { front = []
            , current = ( firstEntry, firstHeight )
            , back = zip restEntries restHeights
            , currentTop = 0
            }
                |> zipFirst

        _ ->
            Nothing


fromListWithFilter :
    String
    -> List (LEntry a)
    -> List Float
    -> Maybe (ZipList a)
fromListWithFilter query entries entryHeights =
    let
        filtered =
            zip entries entryHeights
                |> List.filterMap
                    (\( entry, height ) ->
                        case entry of
                            LEntry a label ->
                                if label |> contains query then
                                    Just ( Entry a, height )
                                else
                                    Nothing

                            LDivider text ->
                                Just ( Divider text, height )
                    )
    in
    case filtered of
        first :: rest ->
            { front = []
            , current = first
            , back = rest
            , currentTop = 0
            }
                |> zipFirst

        _ ->
            Nothing


zipFirst : ZipList a -> Maybe (ZipList a)
zipFirst ({ front, current, back, currentTop } as zipList) =
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
                        |> zipFirst

        _ ->
            Just zipList


zipReverseFirst : ZipList a -> Maybe (ZipList a)
zipReverseFirst ({ front, current, back, currentTop } as zipList) =
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
                        |> zipReverseFirst

        _ ->
            Just zipList


zipNext : ZipList a -> ZipList a
zipNext ({ front, current, back, currentTop } as zipList) =
    case back of
        [] ->
            zipList

        next :: rest ->
            { front = current :: front
            , current = next
            , back = rest
            , currentTop = currentTop + Tuple.second current
            }
                |> zipFirst
                |> Maybe.withDefault zipList


zipPrevious : ZipList a -> ZipList a
zipPrevious ({ front, current, back, currentTop } as zipList) =
    case front of
        [] ->
            zipList

        previous :: rest ->
            { front = rest
            , current = previous
            , back = current :: back
            , currentTop = currentTop - Tuple.second previous
            }
                |> zipReverseFirst
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
                    |> zipNext
                    |> moveForwardToHelper a


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