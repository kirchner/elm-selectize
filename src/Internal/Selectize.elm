module Internal.Selectize
    exposing
        ( Input
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
    , query : String
    , preventBlur : Bool
    , menu : ZipList.State a
    , open : Bool
    }


closed : String -> List (Entry a) -> State a
closed id entries =
    { id = id
    , query = ""
    , preventBlur = False
    , menu = ZipList.init (menuId id) entries
    , open = False
    }



---- UPDATE


type Msg a
    = NoOp
      -- open/close menu
    | OpenMenu
    | CloseMenu
    | FocusTextfield
    | BlurTextfield
    | PreventClosing Bool
      -- query
    | SetQuery String
      -- handle focus and selection
    | Select a
    | SelectKeyboardFocusAndBlur
    | ClearSelection
      -- menu
    | MenuMsg (Msg a) (ZipList.Msg a)


update :
    { select : Maybe a -> msg
    , matches : String -> a -> Bool
    }
    -> Maybe a
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update ({ select, matches } as tagger) selection state msg =
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        OpenMenu ->
            ( { state
                | open = True
                , query = ""
              }
            , Cmd.none
            , Nothing
            )

        CloseMenu ->
            if state.preventBlur then
                ( state, Cmd.none, Nothing )
            else
                ( { state
                    | open = False
                    , query = ""
                  }
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
                ( newMenu, cmd ) =
                    ZipList.filter (matches newQuery) state.menu
            in
            ( { state
                | query = newQuery
                , menu = newMenu
              }
            , cmd |> Cmd.map (MenuMsg NoOp)
            , Just (select Nothing)
            )

        Select a ->
            ( { state
                | open = False
                , query = ""
              }
            , Cmd.none
            , Just (select (Just a))
            )

        SelectKeyboardFocusAndBlur ->
            ( { state
                | open = False
                , query = ""
              }
            , blur state.id
            , Just (select (state.menu.zipList |> Maybe.map ZipList.currentEntry))
            )

        ClearSelection ->
            ( state
            , Cmd.none
            , Just (select Nothing)
            )

        MenuMsg nextMsg menuMsg ->
            let
                ( newMenu, menuCmd ) =
                    ZipList.update selection state.menu menuMsg

                ( newState, cmd, maybeMsg ) =
                    update tagger
                        selection
                        { state | menu = newMenu }
                        nextMsg
            in
            ( newState
            , Cmd.batch
                [ menuCmd |> Cmd.map (MenuMsg NoOp)
                , cmd
                ]
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
    Html.div
        []
        [ config.input
            (buttons config.clearButton config.toggleButton)
            state.id
            selection
            state.query
            state.open
        , ZipList.viewList config state.menu |> mapToNoOp
        , if state.open then
            ZipList.view config
                { select = Select
                , preventClosing = PreventClosing
                , lift = MenuMsg NoOp
                }
                state.menu
          else
            Html.text ""
        ]


path : Decoder a -> Decoder a
path =
    DOM.parentElement
        << DOM.parentElement
        << DOM.childNode 1



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
                , ZipList.onKeydown menuPath
                    (MenuMsg NoOp)
                    (\code ->
                        case code |> fromCode of
                            Enter ->
                                Just SelectKeyboardFocusAndBlur

                            Escape ->
                                Just BlurTextfield

                            _ ->
                                Nothing
                    )
                ]
              else
                [ Events.on "focus"
                    (ZipList.decodeMeasurements path
                        |> Decode.map (MenuMsg OpenMenu)
                    )
                ]
            , noOp (config.attrs (selection /= Nothing) open)
            ]
                |> List.concat

        menuPath =
            DOM.parentElement
                << DOM.parentElement
                << DOM.childNode 2

        actualText =
            selection
                |> Maybe.map config.selection
                |> Maybe.withDefault config.placeholder
    in
    Html.div
        [ Attributes.style
            [ "position" => "relative" ]
        ]
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
              , Events.on "focus"
                    (ZipList.decodeMeasurements path
                        |> Decode.map (MenuMsg OpenMenu)
                    )
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
                , ZipList.onKeydown menuPath
                    (MenuMsg NoOp)
                    (\code ->
                        case code |> fromCode of
                            Enter ->
                                Just SelectKeyboardFocusAndBlur

                            Escape ->
                                Just BlurTextfield

                            _ ->
                                Nothing
                    )
                , Events.onInput SetQuery
                ]
              else
                []
            , noOp (config.attrs (selection /= Nothing) open)
            ]
                |> List.concat

        menuPath =
            DOM.parentElement
                << DOM.parentElement
                << DOM.childNode 2
    in
    Html.div
        [ Attributes.style
            [ "position" => "relative" ]
        ]
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


focus : String -> Cmd (Msg a)
focus id =
    Task.attempt (\_ -> NoOp) <|
        Dom.focus (textfieldId id)


blur : String -> Cmd (Msg a)
blur id =
    Task.attempt (\_ -> NoOp) <|
        Dom.blur (textfieldId id)



---- DECODER


fromResult : Result String a -> Decoder a
fromResult result =
    case result of
        Ok val ->
            Decode.succeed val

        Err reason ->
            Decode.fail reason
