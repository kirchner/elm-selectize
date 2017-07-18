module Selectize.Selectize
    exposing
        ( Entry
        , Msg
        , State
        , UpdateConfig
        , ViewConfig
        , divider
        , empty
        , entry
        , filter
        , first
        , next
        , previous
        , update
        , updateConfig
        , view
        , viewConfig
        , topAndHeight
        )

import DOM
import Dom
import Dom.Scroll
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
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
import List.Extra as List
import Task


{- model -}


type alias State a =
    { query : String
    , keyboardFocus : Maybe a
    , mouseFocus : Maybe a
    , preventBlur : Bool
    , open : Bool
    }


empty : State a
empty =
    { query = ""
    , keyboardFocus = Nothing
    , mouseFocus = Nothing
    , preventBlur = False
    , open = False
    }



{- configuration -}


type alias UpdateConfig a msg model =
    SharedConfig a model { select : Maybe a -> msg }


type alias ViewConfig a model =
    SharedConfig a
        model
        { placeholder : String
        , container : List (Html.Attribute Never)
        , input : Bool -> Bool -> List (Html.Attribute Never)
        , toggle : Bool -> Html Never
        , menu : List (Html.Attribute Never)
        , ul : List (Html.Attribute Never)
        , entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
        }


type alias HtmlDetails msg =
    { attributes : List (Html.Attribute msg)
    , children : List (Html msg)
    }


type alias SharedConfig a model rest =
    { rest
        | toLabel : a -> String
        , state : model -> State a
        , entries : model -> List (Entry a)
        , selection : model -> Maybe a
        , id : String
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


updateConfig :
    { toLabel : a -> String
    , state : model -> State a
    , entries : model -> List (Entry a)
    , selection : model -> Maybe a
    , id : String
    , select : Maybe a -> msg
    }
    -> UpdateConfig a msg model
updateConfig config =
    { toLabel = config.toLabel
    , state = config.state
    , entries = config.entries
    , selection = config.selection
    , id = config.id
    , select = config.select
    }


viewConfig :
    { toLabel : a -> String
    , state : model -> State a
    , entries : model -> List (Entry a)
    , selection : model -> Maybe a
    , id : String
    , placeholder : String
    , container : List (Html.Attribute Never)
    , input : Bool -> Bool -> List (Html.Attribute Never)
    , toggle : Bool -> Html Never
    , menu : List (Html.Attribute Never)
    , ul : List (Html.Attribute Never)
    , entry : a -> Bool -> Bool -> HtmlDetails Never
    , divider : String -> HtmlDetails Never
    }
    -> ViewConfig a model
viewConfig config =
    { toLabel = config.toLabel
    , state = config.state
    , entries = config.entries
    , selection = config.selection
    , id = config.id
    , placeholder = config.placeholder
    , container = config.container
    , input = config.input
    , toggle = config.toggle
    , menu = config.menu
    , ul = config.ul
    , entry = config.entry
    , divider = config.divider
    }



{- update -}


type Msg a
    = NoOp
      -- open/close menu
    | TextfieldFocused (List Int) Int Int
    | TextfieldBlured
    | BlurTextfield
    | SetPreventBlur Bool
      -- query
    | SetQuery String
      -- handle focus and selection
    | SetMouseFocus (Maybe a)
    | Select a
    | SetKeyboardFocus Movement (List Int) Int Int
    | SelectKeyboardFocusAndBlur
    | ClearSelection


type Movement
    = Up
    | Down
    | PageUp
    | PageDown


update :
    UpdateConfig a msg model
    -> model
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update config model msg =
    let
        state =
            config.state model

        entries =
            config.entries model
    in
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        TextfieldFocused entryHeights menuHeight scrollTop ->
            let
                keyboardFocus =
                    case config.selection model of
                        Nothing ->
                            first entries

                        _ ->
                            config.selection model

                ( top, height ) =
                    topAndHeight
                        entryHeights
                        menuHeight
                        scrollTop
                        entries
                        keyboardFocus
            in
            ( { state
                | keyboardFocus = keyboardFocus
                , mouseFocus = Nothing
                , query = ""
                , open = True
              }
            , scroll config.id (top - (menuHeight - height) // 2)
            , Nothing
            )

        TextfieldBlured ->
            if state.preventBlur then
                ( state, Cmd.none, Nothing )
            else
                ( state |> reset
                , Cmd.none
                , Nothing
                )

        BlurTextfield ->
            ( state
            , blur config.id
            , Nothing
            )

        SetPreventBlur preventBlur ->
            ( { state | preventBlur = preventBlur }
            , Cmd.none
            , Nothing
            )

        SetQuery newQuery ->
            ( { state
                | query = newQuery
                , keyboardFocus =
                    entries
                        |> filter config.toLabel newQuery
                        |> first
                , mouseFocus = Nothing
              }
            , scroll config.id 0
            , Just (config.select Nothing)
            )

        SetMouseFocus focus ->
            ( { state | mouseFocus = focus }
            , Cmd.none
            , Nothing
            )

        Select a ->
            ( state |> reset
            , Cmd.none
            , Just (config.select (Just a))
            )

        SetKeyboardFocus movement entryHeights menuHeight scrollTop ->
            let
                filteredEntries =
                    entries
                        |> filter config.toLabel state.query

                nextKeyboardFocus =
                    case movement of
                        Up ->
                            state.keyboardFocus
                                |> Maybe.map
                                    (previous filteredEntries Nothing)

                        Down ->
                            state.keyboardFocus
                                |> Maybe.map (next filteredEntries)

                        _ ->
                            Nothing

                ( top, height ) =
                    topAndHeight
                        entryHeights
                        menuHeight
                        scrollTop
                        filteredEntries
                        nextKeyboardFocus

                y =
                    if (top - 2 * height // 3) < scrollTop then
                        top - 2 * height // 3
                    else if top + 5 * height // 3 > (scrollTop + menuHeight) then
                        top + 5 * height // 3 - menuHeight
                    else
                        scrollTop
            in
            case nextKeyboardFocus of
                Nothing ->
                    ( { state | keyboardFocus = first filteredEntries }
                    , scroll config.id 0
                    , Just (config.select Nothing)
                    )

                Just nextFocus ->
                    ( { state | keyboardFocus = Just nextFocus }
                    , scroll config.id y
                    , Just (config.select Nothing)
                    )

        SelectKeyboardFocusAndBlur ->
            ( state
            , blur config.id
            , Just (config.select state.keyboardFocus)
            )

        ClearSelection ->
            ( state
            , Cmd.none
            , Just (config.select Nothing)
            )


reset : State a -> State a
reset state =
    { state
        | query = ""
        , open = False
        , mouseFocus = Nothing
        , keyboardFocus = Nothing
    }



{- view -}


view : ViewConfig a model -> model -> Html (Msg a)
view config model =
    let
        state =
            config.state model

        selection =
            config.selection model

        filteredEntries =
            config.entries model
                |> filter config.toLabel state.query

        -- attributes
        containerAttrs attrs =
            attrs ++ noOp config.container

        inputAttrs attrs =
            [ [ Attributes.placeholder
                    (selection
                        |> Maybe.map config.toLabel
                        |> Maybe.withDefault config.placeholder
                    )
              , Attributes.value state.query
              , Attributes.id (textfieldId config.id)
              , Events.on "focus" focusDecoder
              ]
            , attrs
            , noOp (config.input (selection /= Nothing) state.open)
            ]
                |> List.concat
    in
    Html.div
        (containerAttrs <|
            if state.open && not (filteredEntries |> List.isEmpty) then
                []
            else
                [ Attributes.style [ ( "overflow", "hidden" ) ] ]
        )
        [ Html.input
            (inputAttrs <|
                if state.open then
                    [ Events.onBlur TextfieldBlured
                    , Events.on "keyup" keyupDecoder
                    , Events.onWithOptions "keydown" keydownOptions keydownDecoder
                    , Events.onInput SetQuery
                    ]
                else
                    []
            )
            []
        , Html.div
            ([ Attributes.id (menuId config.id)
             , Events.onMouseDown (SetPreventBlur True)
             , Events.onMouseUp (SetPreventBlur False)
             ]
                ++ noOp config.menu
            )
            [ filteredEntries
                |> List.map
                    (viewEntry state.open config.entry config.divider state)
                |> Html.ul (noOp config.ul)
            ]
        , Html.div
            [ Attributes.style
                [ ( "pointer-events"
                  , if state.open then
                        "auto"
                    else
                        "none"
                  )
                ]
            ]
            [ config.toggle state.open |> mapToNoOp ]
        ]


focusDecoder : Decoder (Msg a)
focusDecoder =
    Decode.map3
        (\entryHeights menuHeight scrollTop ->
            TextfieldFocused entryHeights menuHeight scrollTop
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
    Decode.map4
        (\code entryHeights menuHeight scrollTop ->
            case code |> fromCode of
                ArrowUp ->
                    Ok (SetKeyboardFocus Up entryHeights menuHeight scrollTop)

                ArrowDown ->
                    Ok (SetKeyboardFocus Down entryHeights menuHeight scrollTop)

                Enter ->
                    Ok SelectKeyboardFocusAndBlur

                Escape ->
                    Ok BlurTextfield

                _ ->
                    Err "not handling that key here"
        )
        Events.keyCode
        entryHeightsDecoder
        menuHeightDecoder
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
    -> State a
    -> Entry a
    -> Html (Msg a)
viewEntry open renderEntry renderDivider state entry =
    let
        { attributes, children } =
            case entry of
                Entry entry ->
                    renderEntry entry
                        (state.mouseFocus == Just entry)
                        (state.keyboardFocus == Just entry)

                Divider title ->
                    renderDivider title

        liAttrs attrs =
            attrs ++ noOp attributes
    in
    Html.li
        (liAttrs <|
            case entry of
                Entry entry ->
                    if open then
                        [ Events.onClick (Select entry)
                        , Events.onMouseEnter (SetMouseFocus (Just entry))
                        , Events.onMouseLeave (SetMouseFocus Nothing)
                        ]
                    else
                        []

                Divider _ ->
                    []
        )
        (children |> List.map mapToNoOp)



{- helper -}


{-| Return all entries which contain the given query. Return the whole
list if the query equals `""`.
-}
filter : (a -> String) -> String -> List (Entry a) -> List (Entry a)
filter toLabel query entries =
    let
        containsQuery entry =
            case entry of
                Entry entry ->
                    toLabel entry
                        |> String.toLower
                        |> String.contains (String.toLower query)

                Divider _ ->
                    True
    in
    entries |> List.filter containsQuery


{-| Return the first entry which is not a `Divider`
-}
first : List (Entry a) -> Maybe a
first entries =
    case entries of
        [] ->
            Nothing

        entry :: rest ->
            case entry of
                Entry entry ->
                    Just entry

                Divider _ ->
                    first rest


{-| Return the entry after the given one, which is not a `Divider`.
Returns the provided entry if there is no next.
-}
next : List (Entry a) -> a -> a
next entries currentFocus =
    case entries of
        [] ->
            currentFocus

        entry :: rest ->
            case entry of
                Entry a ->
                    if a == currentFocus then
                        case rest of
                            entry :: rest ->
                                case entry of
                                    Entry newFocus ->
                                        newFocus

                                    Divider _ ->
                                        next (Entry currentFocus :: rest)
                                            currentFocus

                            [] ->
                                currentFocus
                    else
                        next rest currentFocus

                Divider _ ->
                    next rest currentFocus


{-| Return the entry before (i.e. above) the given one, which is not
a `Divider`. Returns the provided entry if there is no previous.
-}
previous : List (Entry a) -> Maybe a -> a -> a
previous entries former currentFocus =
    case entries of
        [] ->
            currentFocus

        entry :: rest ->
            case entry of
                Entry a ->
                    if a == currentFocus then
                        former
                            |> Maybe.withDefault currentFocus
                    else
                        previous rest (Just a) currentFocus

                Divider _ ->
                    previous rest former currentFocus



{- view helper -}


{-| Compute the distance of the entry to the beginning of the list and
its height, as it is rendered in the DOM.
-}
topAndHeight : List Int -> Int -> Int -> List (Entry a) -> Maybe a -> ( Int, Int )
topAndHeight entryHeights menuHeight scrollTop filteredEntries focus =
    let
        lists =
            List.zip filteredEntries entryHeights
                |> List.splitWhen
                    (\( entry, _ ) ->
                        Just entry == (focus |> Maybe.map Entry)
                    )
    in
    case lists of
        Just ( start, end ) ->
            ( start
                |> List.foldl
                    (\( _, height ) sum -> sum + height)
                    0
            , end
                |> List.head
                |> Maybe.map Tuple.second
                |> Maybe.withDefault 0
            )

        Nothing ->
            ( 0, 0 )


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



{- cmds -}


scroll : String -> Int -> Cmd (Msg a)
scroll id y =
    Task.attempt (\_ -> NoOp) <|
        Dom.Scroll.toY (menuId id) (toFloat y)


blur : String -> Cmd (Msg a)
blur id =
    Task.attempt (\_ -> NoOp) <|
        Dom.blur (textfieldId id)



{- decoder -}


entryHeightsDecoder : Decoder (List Int)
entryHeightsDecoder =
    DOM.target
        :> DOM.parentElement
        :> DOM.childNode 1
        :> DOM.childNode 0
        :> DOM.childNodes
            (Decode.field "offsetHeight" Decode.int)


menuHeightDecoder : Decoder Int
menuHeightDecoder =
    DOM.target
        :> DOM.parentElement
        :> DOM.childNode 1 (Decode.field "clientHeight" Decode.int)


scrollTopDecoder : Decoder Int
scrollTopDecoder =
    DOM.target
        :> DOM.parentElement
        :> DOM.childNode 1 (Decode.field "scrollTop" Decode.int)


fromResult : Result String a -> Decoder a
fromResult result =
    case result of
        Ok val ->
            Decode.succeed val

        Err reason ->
            Decode.fail reason


infixr 5 :>
(:>) : (a -> b) -> a -> b
(:>) f x =
    f x
