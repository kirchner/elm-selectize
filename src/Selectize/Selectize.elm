module Selectize.Selectize
    exposing
        ( Entry
        , LEntry(..)
        , Heights
        , Movement(..)
        , Msg(..)
        , Selector
        , State
        , ViewConfig
        , ZipList
        , button
        , closed
        , currentEntry
        , divider
        , entry
        , filter
        , fromList
        , moveForwardTo
        , textfield
        , update
        , view
        , viewConfig
        , zipCurrentHeight
        , zipCurrentScrollTop
        , zipNext
        , zipPrevious
        )

import DOM
import Dom
import Dom.Scroll
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Html.Keyed
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
    , zipList : Maybe (ZipList a)
    , filteredEntries : Maybe (List (LEntry a))
    , mouseFocus : Maybe a
    , preventBlur : Bool
    , open : Bool

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
    , zipList = Nothing
    , filteredEntries = Just labeledEntries
    , mouseFocus = Nothing
    , preventBlur = False
    , open = False
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
    }
    -> ViewConfig a
viewConfig config =
    { container = config.container
    , menu = config.menu
    , ul = config.ul
    , entry = config.entry
    , divider = config.divider
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
    (Maybe a -> msg)
    -> Maybe a
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update select selection state msg =
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        OpenMenu heights scrollTop ->
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
                        |> Maybe.map zipCurrentScrollTop
                        |> Maybe.withDefault 0

                height =
                    newZipList
                        |> Maybe.map zipCurrentHeight
                        |> Maybe.withDefault 0
            in
            ( { state
                | zipList = newZipList
                , mouseFocus = Nothing
                , query = ""
                , open = True
                , entryHeights = heights.entries
                , menuHeight = heights.menu
                , scrollTop = scrollTop
              }
            , scroll state.id (top - (heights.menu - height) / 2)
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
            , focus state.id
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

                newFilteredEntries =
                    state.entries
                        |> filter newQuery
            in
            ( { state
                | query = newQuery
                , zipList = newZipList
                , filteredEntries = Just newFilteredEntries
                , mouseFocus = Nothing
              }
            , scroll state.id 0
            , Just (select Nothing)
            )

        SetMouseFocus focus ->
            ( { state | mouseFocus = focus }
            , Cmd.none
            , Nothing
            )

        Select a ->
            let
                selection =
                    a |> selectFirst state.entries
            in
            ( state |> reset
            , Cmd.none
            , Just (select (Just a))
            )

        SetKeyboardFocus movement scrollTop ->
            state
                |> updateKeyboardFocus select movement
                |> scrollToKeyboardFocus state.id scrollTop

        SelectKeyboardFocusAndBlur ->
            let
                maybeA =
                    state.zipList |> Maybe.map currentEntry

                selection =
                    maybeA
                        |> Maybe.andThen (selectFirst state.entries)
            in
            ( state |> reset
            , blur state.id
            , Just (select (state.zipList |> Maybe.map currentEntry))
            )

        ClearSelection ->
            ( state
            , Cmd.none
            , Just (select Nothing)
            )


type alias WithKeyboardFocus a r =
    { r | keyboardFocus : Maybe a }


reset : State a -> State a
reset state =
    { state
        | query = ""
        , zipList = Nothing
        , filteredEntries = Nothing
        , open = False
        , mouseFocus = Nothing
    }


updateKeyboardFocus :
    (Maybe a -> msg)
    -> Movement
    -> State a
    -> ( State a, Cmd (Msg a), Maybe msg )
updateKeyboardFocus select movement state =
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
    , Just (select Nothing)
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
                    zipCurrentScrollTop zipList

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


view :
    ViewConfig a
    -> Selector a
    -> Maybe a
    -> State a
    -> Html (Msg a)
view config selector selection state =
    let
        actualEntries =
            state.filteredEntries
                |> Maybe.withDefault state.entries

        keyboardFocus =
            state.zipList |> Maybe.map currentEntry

        selectionText =
            selection
                |> Maybe.andThen (selectFirst actualEntries)
                |> Maybe.map Tuple.second
    in
    Html.div
        [ if state.open && not (actualEntries |> List.isEmpty) then
            Attributes.style
                [ ( "position", "relative" ) ]
          else
            Attributes.style
                [ ( "overflow", "hidden" )
                , ( "position", "relative" )
                ]
        ]
        [ selector
            state.id
            selectionText
            state.query
            state.open
        , Html.div
            ([ Attributes.id (menuId state.id)
             , Events.onMouseDown (PreventClosing True)
             , Events.onMouseUp (PreventClosing False)
             , Attributes.style [ ( "position", "absolute" ) ]
             , Attributes.tabindex -1
             ]
                ++ noOp config.menu
            )
            [ actualEntries
                |> List.map
                    (viewEntry
                        state.open
                        config.entry
                        config.divider
                        keyboardFocus
                        state.mouseFocus
                    )
                |> Html.Keyed.ul (noOp config.ul)
            ]
        ]


type alias Selector a =
    String
    -> Maybe String
    -> String
    -> Bool
    -> Html (Msg a)


button :
    { attrs : Bool -> Bool -> List (Html.Attribute Never)
    , toggleButton : Maybe (Bool -> Html Never)
    , clearButton : Maybe (Html Never)
    , placeholder : String
    }
    -> String
    -> Maybe String
    -> String
    -> Bool
    -> Html (Msg a)
button config id selection _ open =
    let
        buttonAttrs attrs =
            [ [ Attributes.id (textfieldId id)
              , Attributes.tabindex 0
              , Attributes.style
                    [ ( "-webkit-touch-callout", "none" )
                    , ( "-webkit-user-select", "none" )
                    , ( "-moz-user-select", "none" )
                    , ( "-ms-user-select", "none" )
                    , ( "user-select", "none" )
                    ]
              ]
            , attrs
            , noOp (config.attrs (selection /= Nothing) open)
            ]
                |> List.concat

        actualText =
            selection
                |> Maybe.withDefault config.placeholder
    in
    Html.div []
        [ Html.div
            (buttonAttrs <|
                if open then
                    [ Events.onClick BlurTextfield
                    , Events.onBlur CloseMenu
                    , Events.on "keyup" keyupDecoder
                    , Events.onWithOptions "keydown" keydownOptions keydownDecoder
                    ]
                else
                    [ Events.on "focus" focusDecoder
                    ]
            )
            [ Html.text actualText ]
        , buttons
            config.clearButton
            config.toggleButton
            (selection /= Nothing)
            open
        ]


textfield :
    { attrs : Bool -> Bool -> List (Html.Attribute Never)
    , toggleButton : Maybe (Bool -> Html Never)
    , clearButton : Maybe (Html Never)
    , placeholder : String
    }
    -> String
    -> Maybe String
    -> String
    -> Bool
    -> Html (Msg a)
textfield config id selection query open =
    let
        inputAttrs attrs =
            [ if open then
                [ Attributes.placeholder
                    (selection |> Maybe.withDefault config.placeholder)
                , Attributes.value query
                , Attributes.id (textfieldId id)
                , Events.on "focus" focusDecoder
                ]
              else
                [ Attributes.value
                    (selection |> Maybe.withDefault config.placeholder)
                , Attributes.id (textfieldId id)
                , Events.on "focus" focusDecoder
                ]
            , attrs
            , noOp (config.attrs (selection /= Nothing) open)
            ]
                |> List.concat
    in
    Html.div []
        [ Html.input
            (inputAttrs <|
                if open then
                    [ Events.onBlur CloseMenu
                    , Events.on "keyup" keyupDecoder
                    , Events.onWithOptions "keydown" keydownOptions keydownDecoder
                    , Events.onInput SetQuery
                    ]
                else
                    []
            )
            []
        , buttons
            config.clearButton
            config.toggleButton
            (selection /= Nothing)
            open
        ]


buttons :
    Maybe (Html Never)
    -> Maybe (Bool -> Html Never)
    -> Bool
    -> Bool
    -> Html (Msg a)
buttons clearButton toggleButton sthSelected open =
    Html.div
        [ Attributes.style
            [ ( "pointer-events", "auto" )
            , ( "position", "absolute" )
            , ( "right", "0" )
            , ( "top", "0" )
            , ( "display", "flex" )
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


viewEntry :
    Bool
    -> (a -> Bool -> Bool -> HtmlDetails Never)
    -> (String -> HtmlDetails Never)
    -> Maybe a
    -> Maybe a
    -> LEntry a
    -> ( String, Html (Msg a) )
viewEntry open renderEntry renderDivider keyboardFocus mouseFocus entry =
    let
        { attributes, children } =
            case entry of
                LEntry entry label ->
                    renderEntry entry
                        (mouseFocus == Just entry)
                        (keyboardFocus == Just entry)

                LDivider title ->
                    renderDivider title

        liAttrs attrs =
            attrs ++ noOp attributes
    in
    ( case entry of
        LEntry entry label ->
            label

        LDivider title ->
            title
    , Html.li
        (liAttrs <|
            case entry of
                LEntry entry _ ->
                    if open then
                        [ Events.onClick (Select entry)
                        , Events.onMouseEnter (SetMouseFocus (Just entry))
                        , Events.onMouseLeave (SetMouseFocus Nothing)
                        ]
                    else
                        []

                _ ->
                    []
        )
        (children |> List.map mapToNoOp)
    )



---- HELPER


{-| Return all entries which contain the given query. Return the whole
list if the query equals `""`.
-}
filter :
    String
    -> List (LEntry a)
    -> List (LEntry a)
filter query entries =
    let
        containsQuery entry =
            case entry of
                LEntry a label ->
                    if label |> contains query then
                        Just entry
                    else
                        Nothing

                _ ->
                    Just entry
    in
    entries |> List.filterMap containsQuery


contains : String -> String -> Bool
contains query label =
    label
        |> String.toLower
        |> String.contains (String.toLower query)



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


currentEntry : ZipList a -> a
currentEntry zipList =
    case zipList.current of
        ( Entry a, _ ) ->
            a

        _ ->
            -- TODO: remove this! (we need to fix previous and next if
            -- at the beginning or end of the list)
            Debug.crash "this should be impossible"


zipCurrentScrollTop : ZipList a -> Float
zipCurrentScrollTop zipList =
    zipList.currentTop


zipCurrentHeight : ZipList a -> Float
zipCurrentHeight zipList =
    zipList.current |> Tuple.second


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
zipFirst zipList =
    case zipList.current of
        ( Divider _, _ ) ->
            case zipList.back of
                [] ->
                    Nothing

                next :: rest ->
                    zipFirst
                        { front = zipList.current :: zipList.front
                        , current = next
                        , back = rest
                        , currentTop =
                            zipList.currentTop
                                + Tuple.second zipList.current
                        }

        _ ->
            Just zipList


zipReverseFirst : ZipList a -> Maybe (ZipList a)
zipReverseFirst zipList =
    case zipList.current of
        ( Divider _, _ ) ->
            case zipList.front of
                [] ->
                    Nothing

                previous :: rest ->
                    zipReverseFirst
                        { front = rest
                        , current = previous
                        , back = zipList.current :: zipList.back
                        , currentTop =
                            zipList.currentTop
                                - Tuple.second previous
                        }

        _ ->
            Just zipList


zipNext : ZipList a -> ZipList a
zipNext zipList =
    case zipList.back of
        [] ->
            zipList

        next :: rest ->
            { front = zipList.current :: zipList.front
            , current = next
            , back = rest
            , currentTop =
                zipList.currentTop
                    + Tuple.second zipList.current
            }
                |> zipFirst
                |> Maybe.withDefault zipList


zipPrevious : ZipList a -> ZipList a
zipPrevious zipList =
    case zipList.front of
        [] ->
            zipList

        previous :: rest ->
            { front = rest
            , current = previous
            , back = zipList.current :: zipList.back
            , currentTop =
                zipList.currentTop
                    - Tuple.second previous
            }
                |> zipReverseFirst
                |> Maybe.withDefault zipList


moveForwardTo : a -> ZipList a -> ZipList a
moveForwardTo a zipList =
    moveForwardToHelper a zipList
        |> Maybe.withDefault zipList


moveForwardToHelper : a -> ZipList a -> Maybe (ZipList a)
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
