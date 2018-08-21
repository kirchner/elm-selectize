module Selectize.Selectize
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
        , autocomplete
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

--import Keyboard.Extra
--    exposing
--        ( Key(..)
--        , fromCode
--        )

import Browser.Dom as Dom
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Html.Lazy
import Json.Decode as Decode exposing (Decoder)
import Task


---- MODEL


type alias State a =
    { id : String
    , entries : List (LEntry a)
    , query : String
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
        addLabel e =
            case e of
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
update select maybeSelection state msg =
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        OpenMenu heights scrollTop ->
            let
                newZipList =
                    fromList state.entries heights.entries
                        |> Maybe.map
                            (case maybeSelection of
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
            in
            ( { state
                | query = newQuery
                , zipList = newZipList
                , mouseFocus = Nothing
              }
            , scroll state.id 0
            , Just (select Nothing)
            )

        SetMouseFocus newFocus ->
            ( { state | mouseFocus = newFocus }
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
                selection =
                    state.zipList
                        |> Maybe.andThen currentEntry
                        |> Maybe.andThen (selectFirst state.entries)
            in
            ( state |> reset
            , blur state.id
            , Just (select (state.zipList |> Maybe.andThen currentEntry))
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


view :
    ViewConfig a
    -> Maybe a
    -> State a
    -> Html (Msg a)
view config selection state =
    let
        selectionText =
            selection
                |> Maybe.andThen (selectFirst state.entries)
                |> Maybe.map Tuple.second

        menuAttrs =
            [ Attributes.id (menuId state.id)
            , Events.onMouseDown (PreventClosing True)
            , Events.onMouseUp (PreventClosing False)
            , Attributes.style "position" "absolute"
            ]
                ++ noOp config.menu
    in
    case state.zipList of
        Nothing ->
            Html.div
                ((config.container |> noOp)
                    ++ [ Attributes.style "overflow" "hidden"
                       , Attributes.style "position" "relative"
                       ]
                )
                [ config.input
                    state.id
                    selectionText
                    state.query
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
                [ Attributes.style "position" "relative"
                ]
                [ config.input
                    state.id
                    selectionText
                    state.query
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
    ViewConfig a
    -> State a
    -> List (EntryWithHeight a)
    -> List (Html (Msg a))
viewEntries config state front =
    List.map
        (Tuple.first
            >> Html.Lazy.lazy3 viewUnfocusedEntry
                config
                state.mouseFocus
        )
        front


viewCurrentEntry :
    ViewConfig a
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
viewUnfocusedEntry config =
    viewEntry config False


viewFocusedEntry :
    { r
        | entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> Maybe a
    -> Entry a
    -> Html (Msg a)
viewFocusedEntry config =
    viewEntry config True


viewEntry :
    { r
        | entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
    }
    -> Bool
    -> Maybe a
    -> Entry a
    -> Html (Msg a)
viewEntry config keyboardFocused mouseFocus e =
    let
        { attributes, children } =
            case e of
                Entry actualEntry ->
                    config.entry actualEntry
                        (mouseFocus == Just actualEntry)
                        keyboardFocused

                Divider title ->
                    config.divider title

        liAttrs attrs =
            attrs ++ noOp attributes
    in
    Html.li
        (liAttrs <|
            case e of
                Entry actualEntry ->
                    [ Events.onClick (Select actualEntry)
                    , Events.onMouseEnter (SetMouseFocus (Just actualEntry))
                    , Events.onMouseLeave (SetMouseFocus Nothing)
                    ]

                _ ->
                    []
        )
        (children |> List.map mapToNoOp)


type alias Input a =
    String
    -> Maybe String
    -> String
    -> Bool
    -> Html (Msg a)


simple :
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
simple config id selection _ open =
    let
        buttonAttrs =
            [ [ Attributes.id (textfieldId id)
              , Attributes.tabindex 0
              , Attributes.style "-webkit-touch-callout" "none"
              , Attributes.style "-webkit-user-select" "none"
              , Attributes.style "-moz-user-select" "none"
              , Attributes.style "-ms-user-select" "none"
              , Attributes.style "user-select" "none"
              ]
            , if open then
                [ Events.onBlur CloseMenu
                , Events.on "keyup" keyupDecoder
                , Events.preventDefaultOn "keydown" keydownDecoder
                ]
              else
                [ Events.on "focus" focusDecoder ]
            , noOp (config.attrs (selection /= Nothing) open)
            ]
                |> List.concat

        actualText =
            selection
                |> Maybe.withDefault config.placeholder
    in
    Html.div []
        [ Html.div buttonAttrs
            [ Html.text actualText ]
        , buttons
            config.clearButton
            config.toggleButton
            (selection /= Nothing)
            open
        ]


autocomplete :
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
autocomplete config id selection query open =
    let
        inputAttrs =
            [ [ Attributes.value query
              , Attributes.id (textfieldId id)
              , Events.on "focus" focusDecoder
              ]
            , if selection == Nothing then
                if open then
                    [ Attributes.placeholder config.placeholder ]
                else
                    [ Attributes.value config.placeholder ]
              else
                [ Attributes.style "color" "transparent" ]
            , if open then
                [ Events.onBlur CloseMenu
                , Events.on "keyup" keyupDecoder
                , Events.preventDefaultOn "keydown" keydownDecoder
                , Events.onInput SetQuery
                ]
              else
                []
            , noOp (config.attrs (selection /= Nothing) open)
            ]
                |> List.concat
    in
    Html.div []
        [ Html.input inputAttrs []
        , Html.div
            ([ Attributes.style "position" "absolute"
             , Attributes.style "width" "100%"
             , Attributes.style "height" "100%"
             , Attributes.style "left" "0"
             , Attributes.style "top" "0"
             , Attributes.style "pointer-events" "none"
             , Attributes.style "border-color" "transparent"
             , Attributes.style "background-color" "transparent"
             , Attributes.style "box-shadow" "none"
             ]
                ++ noOp (config.attrs (selection /= Nothing) open)
            )
            [ Html.text (selection |> Maybe.withDefault "") ]
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
        [ Attributes.style "position" "absolute"
        , Attributes.style "right" "0"
        , Attributes.style "top" "0"
        , Attributes.style "display" "flex"
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
                            Events.preventDefaultOn "click"
                                (Decode.succeed ( BlurTextfield, True ))

                        False ->
                            Events.preventDefaultOn "click"
                                (Decode.succeed ( FocusTextfield, True ))
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


keydownDecoder : Decoder ( Msg a, Bool )
keydownDecoder =
    Decode.map2
        (\code scrollTop ->
            case code of
                38 ->
                    Ok ( SetKeyboardFocus Up scrollTop, True )

                40 ->
                    Ok ( SetKeyboardFocus Down scrollTop, True )

                13 ->
                    Ok ( SelectKeyboardFocusAndBlur, True )

                27 ->
                    Ok ( BlurTextfield, True )

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
                case code of
                    8 ->
                        Ok ClearSelection

                    46 ->
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
        (Dom.getViewportOf (menuId id)
            |> Task.andThen
                (\{ viewport } ->
                    Dom.setViewportOf (menuId id) viewport.x y
                )
        )


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
    let
        loop idx xs =
            Decode.maybe
                (Decode.at
                    [ String.fromInt idx
                    , "offsetHeight"
                    ]
                    Decode.float
                )
                |> Decode.andThen
                    (Maybe.map (\x -> loop (idx + 1) (x :: xs))
                        >> Maybe.withDefault (Decode.succeed xs)
                    )
    in
    Decode.map List.reverse <|
        Decode.at
            [ "target"
            , "parentElement"
            , "parentElement"
            , "childNodes"
            , "1"
            , "childNodes"
            , "0"
            , "childNodes"
            ]
            (loop 0 [])


menuHeightDecoder : Decoder Float
menuHeightDecoder =
    Decode.at
        [ "target"
        , "parentElement"
        , "parentElement"
        , "childNodes"
        , "1"
        , "clientHeight"
        ]
        Decode.float


scrollTopDecoder : Decoder Float
scrollTopDecoder =
    Decode.at
        [ "target"
        , "parentElement"
        , "parentElement"
        , "childNodes"
        , "1"
        , "scrollTop"
        ]
        Decode.float


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


currentEntry : { r | current : EntryWithHeight a } -> Maybe a
currentEntry { current } =
    case current of
        ( Entry a, _ ) ->
            Just a

        _ ->
            Nothing


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
                    (\( e, height ) ->
                        case e of
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
