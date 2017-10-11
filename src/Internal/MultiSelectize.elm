module Internal.MultiSelectize
    exposing
        ( Action
        , Heights
        , Input
        , Movement(..)
        , Msg(..)
        , State
        , ViewConfig
        , closed
        , simple
        , unselectOn
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
import Html.Lazy
import Internal.Entry as Entry exposing (Entry(..))
import Internal.ZipList as ZipList exposing (EntryWithHeight, ZipList)
import Json.Decode as Decode exposing (Decoder)
import Keyboard.Extra
    exposing
        ( Key
            ( ArrowDown
            , ArrowLeft
            , ArrowRight
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
    , queryWidth : Float
    , queryPosition : Int
    , zipList : Maybe (ZipList a)
    , unfilteredZipList : Maybe (ZipList a)
    , open : Bool
    , mouseFocus : Maybe a
    , preventClose : Bool

    -- dom measurements
    , entryHeights : List Float
    , menuHeight : Float
    , scrollTop : Float
    }


type alias SimpleState a =
    { state : State a
    , selections : List a
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
    , queryWidth = 0
    , queryPosition = 0
    , zipList = Nothing
    , unfilteredZipList = Nothing
    , open = False
    , mouseFocus = Nothing
    , preventClose = False
    , entryHeights = []
    , menuHeight = 0
    , scrollTop = 0
    }


simpleClosed : String -> List (Entry a) -> SimpleState a
simpleClosed id entries =
    { state = closed id entries
    , selections = []
    }


selections : SimpleState a -> List a
selections simpleState =
    simpleState.selections



---- UPDATE


type Msg a
    = NoOp
      -- open/close menu
    | OpenMenu Heights Float
    | CloseMenu
    | FocusTextfield
    | BlurTextfield
    | PreventClose Bool
      -- query
    | SetQuery String
    | SetQueryWidth Float
    | MoveQueryLeft
    | MoveQueryRight
      -- handle focus and selection
    | SetMouseFocus (Maybe a)
    | Select a
    | SetKeyboardFocus Movement Float
    | SelectKeyboardFocus
    | ClearSelection
    | UnselectAt Int
    | ClearPreviousSelection


type Movement
    = Up
    | Down
    | PageUp
    | PageDown


type TopMsg a
    = TopSelect Int a
    | TopUnselect Int
    | TopClearSelection


simplestUpdate :
    { keepQuery : Bool
    , textfieldMovable : Bool
    }
    -> SimpleState String
    -> Msg String
    -> ( SimpleState String, Cmd (Msg String) )
simplestUpdate { keepQuery, textfieldMovable } simpleState msg =
    let
        contains query string =
            string
                |> String.toLower
                |> String.contains
                    (query |> String.toLower)
    in
    simpleUpdate
        { keepQuery = keepQuery
        , textfieldMovable = textfieldMovable
        , matches = contains
        }
        simpleState
        msg


simpleUpdate :
    { keepQuery : Bool
    , textfieldMovable : Bool
    , matches : String -> a -> Bool
    }
    -> SimpleState a
    -> Msg a
    -> ( SimpleState a, Cmd (Msg a) )
simpleUpdate { keepQuery, textfieldMovable, matches } simpleState msg =
    let
        ( newState, cmd, maybeTopMsg ) =
            update
                { select = TopSelect
                , unselect = TopUnselect
                , clearSelection = TopClearSelection
                , keepQuery = keepQuery
                , textfieldMovable = textfieldMovable
                , matches = matches
                }
                simpleState.selections
                simpleState.state
                msg

        newSimpleState =
            { simpleState | state = newState }
    in
    case maybeTopMsg of
        Just (TopSelect position newSelection) ->
            ( { newSimpleState
                | selections =
                    [ simpleState.selections |> List.take position
                    , [ newSelection ]
                    , simpleState.selections |> List.drop position
                    ]
                        |> List.concat
              }
            , cmd
            )

        Just (TopUnselect position) ->
            ( { newSimpleState
                | selections =
                    [ simpleState.selections |> List.take position
                    , simpleState.selections |> List.drop (position + 1)
                    ]
                        |> List.concat
              }
            , cmd
            )

        Just TopClearSelection ->
            ( { newSimpleState | selections = [] }, cmd )

        Nothing ->
            ( newSimpleState, cmd )


update :
    { select : Int -> a -> msg
    , unselect : Int -> msg
    , clearSelection : msg
    , keepQuery : Bool
    , textfieldMovable : Bool
    , matches : String -> a -> Bool
    }
    -> List a
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update { select, unselect, clearSelection, keepQuery, textfieldMovable, matches } selections state msg =
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        OpenMenu heights scrollTop ->
            if state.open then
                ( { state | preventClose = False }
                , Cmd.none
                , Nothing
                )
            else
                let
                    entries =
                        state.entries
                            |> filterOut selections

                    newZipList =
                        ZipList.fromList entries heights.entries

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
                    , unfilteredZipList = newZipList
                    , open = True
                    , mouseFocus = Nothing
                    , query = ""
                    , entryHeights = heights.entries
                    , menuHeight = heights.menu
                    , scrollTop = scrollTop
                  }
                , Cmd.batch
                    [ if state.open then
                        Cmd.none
                      else
                        scroll state.id (top - (heights.menu - height) / 2)
                    , focus state.id
                    ]
                , Nothing
                )

        CloseMenu ->
            if state.preventClose then
                ( state
                , Cmd.none
                , Nothing
                )
            else
                ( { state
                    | query = ""
                    , queryWidth = 0
                    , queryPosition = 0
                    , zipList = Nothing
                    , open = False
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

        PreventClose preventClose ->
            ( { state | preventClose = preventClose }
            , Cmd.none
            , Nothing
            )

        SetQuery newQuery ->
            let
                entries =
                    state.entries
                        |> filterOut selections

                newZipList =
                    ZipList.fromListWithFilter (matches newQuery) entries state.entryHeights
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
            ( { state | queryWidth = newWidth }
            , Cmd.none
            , Nothing
            )

        MoveQueryLeft ->
            if textfieldMovable then
                ( { state
                    | queryPosition =
                        (state.queryPosition + 1)
                            |> Basics.clamp 0 (List.length selections)
                    , preventClose = True
                  }
                , focus state.id
                , Nothing
                )
            else
                ( state
                , Cmd.none
                , Nothing
                )

        MoveQueryRight ->
            ( { state
                | queryPosition =
                    (state.queryPosition - 1)
                        |> Basics.clamp 0 (List.length selections)
              }
            , focus state.id
            , Nothing
            )

        SetMouseFocus focus ->
            ( { state | mouseFocus = focus }
            , Cmd.none
            , Nothing
            )

        Select a ->
            let
                entries =
                    state.entries
                        |> filterOut (a :: selections)

                newZipList =
                    ZipList.fromList entries state.entryHeights
            in
            ( { state
                | query = ""
                , zipList = newZipList
              }
            , focus state.id
            , Just (select state.queryPosition a)
            )

        SetKeyboardFocus movement scrollTop ->
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

                cmd =
                    case newZipList of
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
                            scroll state.id y

                        Nothing ->
                            Cmd.none
            in
            ( { state | zipList = newZipList }
            , cmd
            , Nothing
            )

        SelectKeyboardFocus ->
            case state.zipList |> Maybe.map ZipList.currentEntry of
                Just a ->
                    let
                        entries =
                            state.entries
                                |> filterOut (a :: selections)

                        newZipList =
                            if keepQuery || state.query == "" then
                                state.zipList |> Maybe.andThen ZipList.removeCurrentEntry
                            else
                                ZipList.fromList entries state.entryHeights
                    in
                    ( { state
                        | query =
                            if keepQuery then
                                state.query
                            else
                                ""
                        , zipList = newZipList
                      }
                    , Cmd.batch
                        [ focus state.id
                        , if keepQuery || state.query == "" then
                            Cmd.none
                          else
                            scroll state.id 0
                        ]
                    , Just (select state.queryPosition a)
                    )

                Nothing ->
                    ( state
                    , Cmd.none
                    , Nothing
                    )

        ClearSelection ->
            ( state
            , Cmd.none
            , Just clearSelection
            )

        UnselectAt position ->
            ( state
            , focus state.id
            , Just (unselect position)
            )

        ClearPreviousSelection ->
            let
                actualSelections =
                    [ selections |> List.take state.queryPosition
                    , selections |> List.drop (state.queryPosition + 1)
                    ]
                        |> List.concat

                entries =
                    state.entries
                        |> filterOut actualSelections

                newZipList =
                    ZipList.fromList entries state.entryHeights
            in
            ( { state
                | zipList = newZipList
              }
            , Cmd.batch
                [ focus state.id
                , scroll state.id 0
                ]
            , Just (unselect state.queryPosition)
            )


filterOut : List a -> List (Entry a) -> List (Entry a)
filterOut selections entries =
    let
        isNotSelected entry =
            case entry of
                Entry a ->
                    selections
                        |> List.any (\selection -> selection == a)
                        |> not

                _ ->
                    True
    in
    entries
        |> List.filter isNotSelected



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



---- VIEW


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


view : ViewConfig a -> List a -> State a -> Html (Msg a)
view config selections state =
    let
        selectionTexts =
            selections
                |> List.filterMap (Entry.selectFirst state.entries)

        menuAttrs =
            [ Attributes.id (menuId state.id)
            , Events.onMouseDown (PreventClose True)
            , Events.onMouseUp (PreventClose False)
            , Attributes.style [ "position" => "absolute" ]
            ]
                ++ noOp config.menu

        input =
            config.input
                state.id
                selectionTexts
                state.query
                state.queryWidth
                state.queryPosition
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
                , Html.div menuAttrs
                    [ state.entries
                        |> List.map
                            (viewUnfocusedEntry config Nothing)
                        |> Html.ul (noOp config.ul)
                    ]
                ]

        Just zipList ->
            Html.div
                [ Attributes.style
                    [ "position" => "relative" ]
                ]
                [ input
                , Html.div menuAttrs
                    [ [ zipList.front
                            |> viewEntries config state
                            |> List.reverse
                      , [ zipList.current
                            |> Tuple.first
                            |> viewEntry config True state.mouseFocus
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



---- VIEW INPUT


type alias Input a =
    String
    -> List a
    -> String
    -> Float
    -> Int
    -> Bool
    -> Html (Msg a)


type Action
    = Unselect


unselectOn : String -> Html.Attribute Action
unselectOn event =
    Events.onWithOptions event
        { stopPropagation = True
        , preventDefault = False
        }
        (Decode.succeed Unselect)


simple :
    { attrs : Bool -> List (Html.Attribute Never)
    , selection : a -> Html Action
    , placeholder : Bool -> Html Never
    , textfieldClass : String
    }
    -> String
    -> List a
    -> String
    -> Float
    -> Int
    -> Bool
    -> Html (Msg a)
simple config id selections query queryWidth queryPosition open =
    let
        rightSelections =
            selections
                |> List.take queryPosition
                |> List.map config.selection
                |> List.indexedMap (mapActions 0)

        leftSelections =
            selections
                |> List.drop queryPosition
                |> List.map config.selection
                |> List.indexedMap (mapActions queryPosition)

        placeholder =
            if
                (rightSelections |> List.isEmpty)
                    && (leftSelections |> List.isEmpty)
                    && (query == "")
            then
                Just (config.placeholder open)
            else
                Nothing

        content =
            [ rightSelections
            , [ textfield id config.textfieldClass query queryWidth placeholder ]
            , leftSelections
            ]
                |> List.concat
                |> List.reverse
    in
    Html.div []
        [ Html.div
            ([ Events.onClick FocusTextfield
             , Events.onMouseDown (PreventClose True)
             , Events.onMouseUp (PreventClose False)
             , Attributes.style
                [ "position" => "relative" ]
             ]
                ++ noOp (config.attrs open)
            )
            content
        ]


textfield : String -> String -> String -> Float -> Maybe (Html Never) -> Html (Msg a)
textfield id textfieldClass query queryWidth placeholder =
    let
        queryWidthDecoder callback =
            Decode.field "offsetWidth" Decode.float
                |> DOM.childNode 0
                |> DOM.childNode 0
                |> DOM.parentElement
                |> DOM.target
                |> Decode.map callback

        keydownDecoder =
            DOM.childNode 1 (Decode.field "scrollTop" Decode.float)
                |> DOM.parentElement
                |> DOM.parentElement
                |> DOM.parentElement
                |> DOM.parentElement
                |> DOM.target
                |> Decode.andThen
                    (\scrollTop ->
                        keyDecoder
                            |> onKey ArrowUp (SetKeyboardFocus Up scrollTop)
                            |> onKey ArrowDown (SetKeyboardFocus Down scrollTop)
                            |> onKey Enter SelectKeyboardFocus
                            |> onKey Escape BlurTextfield
                            |> (if query == "" then
                                    \result ->
                                        result
                                            |> onKey BackSpace ClearPreviousSelection
                                            |> onKey ArrowLeft MoveQueryLeft
                                            |> onKey ArrowRight MoveQueryRight
                                            |> doIt
                                else
                                    doIt
                               )
                    )
    in
    Html.div
        [ Attributes.style
            [ "display" => "flex" ]
        ]
        [ Html.div
            [ Attributes.style
                [ "width" => "0"
                , "overflow" => "hidden"
                , "display" => "flex"
                ]
            ]
            [ Html.span
                [ Attributes.class textfieldClass
                , Attributes.style
                    [ "border" => "0"
                    , "padding" => "0"
                    , "margin" => "0"
                    , "white-space" => "nowrap"
                    ]
                ]
                [ Html.text query ]
            ]
        , Html.input
            [ Attributes.id (textfieldId id)
            , Attributes.class textfieldClass
            , Attributes.style
                [ "width" => (toString (queryWidth + 10) ++ "px") ]
            , Events.onInput SetQuery
            , Events.onWithOptions "keydown"
                { stopPropagation = True
                , preventDefault = True
                }
                keydownDecoder
            , Events.on "keyup" (queryWidthDecoder SetQueryWidth)
            , Events.onBlur CloseMenu
            , Events.on "focus" (measurementsDecoder OpenMenu)
            , Attributes.value query
            ]
            []
        , case placeholder of
            Just placeholder ->
                Html.div
                    [ Attributes.style
                        [ ( "position", "absolute" )
                        , ( "z-index", "10" )
                        ]
                    ]
                    [ placeholder |> mapToNoOp ]

            Nothing ->
                Html.text ""
        ]


measurementsDecoder : ({ entries : List Float, menu : Float } -> Float -> msg) -> Decoder msg
measurementsDecoder callback =
    Decode.map3
        (\entryHeights menuHeight scrollTop ->
            callback { entries = entryHeights, menu = menuHeight } scrollTop
        )
        entryHeightsDecoder
        menuHeightDecoder
        scrollTopDecoder


entryHeightsDecoder : Decoder (List Float)
entryHeightsDecoder =
    Decode.field "offsetHeight" Decode.float
        |> DOM.childNodes
        |> DOM.childNode 0
        |> DOM.childNode 1
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.target


menuHeightDecoder : Decoder Float
menuHeightDecoder =
    DOM.childNode 1 (Decode.field "clientHeight" Decode.float)
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.target


scrollTopDecoder : Decoder Float
scrollTopDecoder =
    DOM.childNode 1 (Decode.field "scrollTop" Decode.float)
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.parentElement
        |> DOM.target



---- HELPER


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


mapActions : Int -> Int -> Html Action -> Html (Msg a)
mapActions offset position node =
    node
        |> Html.map
            (\action ->
                case action of
                    Unselect ->
                        UnselectAt (position + offset)
            )



---- DECODER


keyDecoder : Decoder (Result Key msg)
keyDecoder =
    Events.keyCode
        |> Decode.map (fromCode >> Err)


onKey : Key -> msg -> Decoder (Result Key msg) -> Decoder (Result Key msg)
onKey code msg decoder =
    decoder
        |> Decode.andThen
            (\result ->
                case result of
                    Ok msg ->
                        Decode.succeed (Ok msg)

                    Err actualCode ->
                        if actualCode == code then
                            Decode.succeed (Ok msg)
                        else
                            Decode.succeed (Err actualCode)
            )


doIt : Decoder (Result Key msg) -> Decoder msg
doIt decoder =
    decoder
        |> Decode.andThen
            (\result ->
                case result of
                    Ok msg ->
                        Decode.succeed msg

                    Err _ ->
                        Decode.fail "not handling that key here"
            )
