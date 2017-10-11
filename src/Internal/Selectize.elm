module Internal.Selectize
    exposing
        ( Heights
        , Input
        , Movement(..)
        , Msg(..)
        , State
        , ViewConfig
        , autocomplete
        , closed
        , contains
        , simple
        , update
        , view
        , viewConfig
        )

import DOM
import Dom
import Dom.Scroll
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Internal.Entry as Entry exposing (Entry(..))
import Internal.ZipList as ZipList exposing (Direction, EntryWithHeight, ZipList)
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


closed : String -> List (Entry a) -> State a
closed id entries =
    { id = id
    , entries = entries
    , query = ""
    , zipList = Nothing
    , open = False
    , mouseFocus = Nothing
    , preventBlur = False
    , entryHeights = []
    , menuHeight = 0
    , scrollTop = 0
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
    { select : Maybe a -> msg
    , matches : String -> a -> Bool
    }
    -> Maybe a
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update { select, matches } selection state msg =
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        OpenMenu heights scrollTop ->
            let
                newZipList =
                    ZipList.fromList state.entries heights.entries
                        |> Maybe.map
                            (case selection of
                                Just a ->
                                    ZipList.moveForwardTo a

                                Nothing ->
                                    identity
                            )

                top =
                    newZipList
                        |> Maybe.map .currentTop
                        |> Maybe.withDefault 0

                height =
                    newZipList
                        |> Maybe.map ZipList.currentHeight
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
                    ZipList.fromListWithFilter matches newQuery state.entries state.entryHeights
            in
            ( { state
                | query = newQuery
                , zipList = newZipList
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
                    state.zipList |> Maybe.map ZipList.currentEntry
            in
            ( state |> reset
            , blur state.id
            , Just (select (state.zipList |> Maybe.map ZipList.currentEntry))
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
                        |> Maybe.map ZipList.previous

                Down ->
                    state.zipList
                        |> Maybe.map ZipList.next

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
                    ZipList.currentHeight zipList

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



---- CONFIGURATION


type alias ViewConfig a =
    { container : List (Html.Attribute Never)
    , menu : List (Html.Attribute Never)
    , ul : List (Html.Attribute Never)
    , entry : a -> Bool -> Bool -> HtmlDetails Never
    , divider : String -> HtmlDetails Never
    , toggleButton : Maybe (Bool -> Html Never)
    , clearButton : Maybe (Html Never)
    , direction : Direction
    , input : Input a
    }


type alias HtmlDetails msg =
    { attributes : List (Html.Attribute msg)
    , children : List (Html msg)
    }


viewConfig :
    { container : List (Html.Attribute Never)
    , menu : List (Html.Attribute Never)
    , ul : List (Html.Attribute Never)
    , entry : a -> Bool -> Bool -> HtmlDetails Never
    , divider : String -> HtmlDetails Never
    , toggleButton : Maybe (Bool -> Html Never)
    , clearButton : Maybe (Html Never)
    , direction : Direction
    , input : Input a
    }
    -> ViewConfig a
viewConfig config =
    { container = config.container
    , menu = config.menu
    , ul = config.ul
    , entry = config.entry
    , divider = config.divider
    , toggleButton = config.toggleButton
    , clearButton = config.clearButton
    , direction = config.direction
    , input = config.input
    }



---- VIEW


view :
    ViewConfig a
    -> Maybe a
    -> State a
    -> Html (Msg a)
view config selection state =
    let
        menuAttrs =
            [ Attributes.id (menuId state.id)
            , Events.onMouseDown (PreventClosing True)
            , Events.onMouseUp (PreventClosing False)
            , Attributes.style [ "position" => "absolute" ]
            ]
                ++ noOp config.menu

        input =
            config.input
                (buttons config.clearButton config.toggleButton)
                state.id
                selection
                state.query
                state.open
    in
    case state.zipList of
        Nothing ->
            Html.div
                [ Attributes.style
                    [ "overflow" => "hidden"
                    , "position" => "relative"
                    ]
                ]
                [ input
                , ZipList.viewList
                    config
                    { select = Select
                    , setMouseFocus = SetMouseFocus
                    , preventClosing = PreventClosing
                    }
                    (menuId state.id)
                    state.entries
                    state.mouseFocus
                ]

        Just zipList ->
            Html.div
                [ Attributes.style
                    [ "position" => "relative" ]
                ]
                [ input
                , ZipList.view
                    config
                    { select = Select
                    , setMouseFocus = SetMouseFocus
                    , preventClosing = PreventClosing
                    }
                    (menuId state.id)
                    zipList
                    state.mouseFocus
                ]



---- VIEW INPUT


type alias Input a =
    (Bool -> Bool -> Html (Msg a))
    -> String
    -> Maybe a
    -> String
    -> Bool
    -> Html (Msg a)


simple :
    { attrs : Bool -> Bool -> List (Html.Attribute Never)
    , selection : a -> String
    , placeholder : String
    }
    -> (Bool -> Bool -> Html (Msg a))
    -> String
    -> Maybe a
    -> String
    -> Bool
    -> Html (Msg a)
simple config buttons id selection _ open =
    let
        buttonAttrs =
            [ [ Attributes.id (textfieldId id)
              , Attributes.tabindex 0
              , Attributes.style
                    [ "-webkit-touch-callout" => "none"
                    , "-webkit-user-select" => "none"
                    , "-moz-user-select" => "none"
                    , "-ms-user-select" => "none"
                    , "user-select" => "none"
                    ]
              ]
            , if open then
                [ Events.onBlur CloseMenu
                , Events.on "keyup" keyupDecoder
                , Events.onWithOptions "keydown" keydownOptions keydownDecoder
                ]
              else
                [ Events.on "focus" focusDecoder ]
            , noOp (config.attrs (selection /= Nothing) open)
            ]
                |> List.concat

        actualText =
            selection
                |> Maybe.map config.selection
                |> Maybe.withDefault config.placeholder
    in
    Html.div []
        [ Html.div buttonAttrs
            [ Html.text actualText ]
        , buttons (selection /= Nothing) open
        ]


autocomplete :
    { attrs : Bool -> Bool -> List (Html.Attribute Never)
    , selection : a -> String
    , placeholder : String
    }
    -> (Bool -> Bool -> Html (Msg a))
    -> String
    -> Maybe a
    -> String
    -> Bool
    -> Html (Msg a)
autocomplete config buttons id selection query open =
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
                [ Attributes.style
                    [ "color" => "transparent" ]
                ]
            , if open then
                [ Events.onBlur CloseMenu
                , Events.on "keyup" keyupDecoder
                , Events.onWithOptions "keydown" keydownOptions keydownDecoder
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
            ([ Attributes.style
                [ "position" => "absolute"
                , "width" => "100%"
                , "height" => "100%"
                , "left" => "0"
                , "top" => "0"
                , "pointer-events" => "none"
                , "border-color" => "transparent"
                , "background-color" => "transparent"
                , "box-shadow" => "none"
                ]
             ]
                ++ noOp (config.attrs (selection /= Nothing) open)
            )
            [ selection
                |> Maybe.map config.selection
                |> Maybe.withDefault ""
                |> Html.text
            ]
        , buttons (selection /= Nothing) open
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
