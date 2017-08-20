module Selectize.Selectize
    exposing
        ( Entry
        , Heights
        , Movement(..)
        , Msg(..)
        , State
        , ViewConfig
        , divider
        , empty
        , entry
        , filter
        , first
        , next
        , previous
        , topAndHeight
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
import Html.Keyed
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


{- model -}


type alias State a =
    { query : String
    , keyboardFocus : Maybe a
    , mouseFocus : Maybe a
    , preventBlur : Bool
    , open : Bool

    -- dom measurements
    , heights : Maybe Heights
    , scrollTop : Float
    }


type alias Heights =
    { entries : List Float
    , menu : Float
    }


empty : State a
empty =
    { query = ""
    , keyboardFocus = Nothing
    , mouseFocus = Nothing
    , preventBlur = False
    , open = False
    , heights = Nothing
    , scrollTop = 0
    }



{- configuration -}


type alias ViewConfig a =
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
    { placeholder : String
    , container : List (Html.Attribute Never)
    , input : Bool -> Bool -> List (Html.Attribute Never)
    , toggle : Bool -> Html Never
    , menu : List (Html.Attribute Never)
    , ul : List (Html.Attribute Never)
    , entry : a -> Bool -> Bool -> HtmlDetails Never
    , divider : String -> HtmlDetails Never
    }
    -> ViewConfig a
viewConfig config =
    { placeholder = config.placeholder
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
    | OpenMenu Heights Float
    | CloseMenu
    | BlurTextfield
    | PreventClosing Bool
      -- query
    | SetQuery String
      -- handle focus and selection
    | SetMouseFocus (Maybe a)
    | Select a
    | SetKeyboardFocus Movement (Maybe Heights) Float
    | SelectKeyboardFocusAndBlur
    | ClearSelection


type Movement
    = Up
    | Down
    | PageUp
    | PageDown


update :
    String
    -> (a -> String)
    -> (Maybe a -> msg)
    -> List (Entry a)
    -> Maybe a
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update id toLabel select entries selection state msg =
    case msg of
        NoOp ->
            ( state, Cmd.none, Nothing )

        OpenMenu heights scrollTop ->
            let
                keyboardFocus =
                    case selection of
                        Nothing ->
                            first entries

                        _ ->
                            selection

                ( top, height ) =
                    topAndHeight heights.entries entries keyboardFocus
            in
            ( { state
                | keyboardFocus = keyboardFocus
                , mouseFocus = Nothing
                , query = ""
                , open = True
                , heights = Just heights
                , scrollTop = scrollTop
              }
            , scroll id (top - (heights.menu - height) / 2)
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

        BlurTextfield ->
            ( state
            , blur id
            , Nothing
            )

        PreventClosing preventBlur ->
            ( { state | preventBlur = preventBlur }
            , Cmd.none
            , Nothing
            )

        SetQuery newQuery ->
            ( { state
                | query = newQuery
                , keyboardFocus =
                    entries
                        |> filter toLabel newQuery
                        |> first
                , mouseFocus = Nothing
              }
                |> resetHeights
            , scroll id 0
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

        SetKeyboardFocus movement maybeHeights scrollTop ->
            let
                filteredEntries =
                    entries |> filter toLabel state.query
            in
            state
                |> updateHeights maybeHeights
                |> updateKeyboardFocus select filteredEntries movement
                |> scrollToKeyboardFocus id filteredEntries scrollTop

        SelectKeyboardFocusAndBlur ->
            ( state |> reset
            , blur id
            , Just (select state.keyboardFocus)
            )

        ClearSelection ->
            ( state
            , Cmd.none
            , Just (select Nothing)
            )


type alias WithKeyboardFocus a r =
    { r | keyboardFocus : Maybe a }


type alias WithHeights r =
    { r | heights : Maybe Heights }


reset : State a -> State a
reset state =
    { state
        | query = ""
        , open = False
        , mouseFocus = Nothing
        , keyboardFocus = Nothing
    }


resetHeights : WithHeights r -> WithHeights r
resetHeights state =
    { state | heights = Nothing }


updateHeights : Maybe Heights -> WithHeights r -> WithHeights r
updateHeights maybeHeights state =
    case maybeHeights of
        Just newHeights ->
            { state | heights = Just newHeights }

        Nothing ->
            state


updateKeyboardFocus :
    (Maybe a -> msg)
    -> List (Entry a)
    -> Movement
    -> WithKeyboardFocus a r
    -> ( WithKeyboardFocus a r, Cmd (Msg a), Maybe msg )
updateKeyboardFocus select filteredEntries movement state =
    let
        nextKeyboardFocus =
            case movement of
                Up ->
                    state.keyboardFocus
                        |> Maybe.map (previous filteredEntries)

                Down ->
                    state.keyboardFocus
                        |> Maybe.map (next filteredEntries)

                _ ->
                    Nothing
    in
    ( { state
        | keyboardFocus =
            case nextKeyboardFocus of
                Nothing ->
                    first filteredEntries

                Just nextFocus ->
                    Just nextFocus
      }
    , Cmd.none
    , Just (select Nothing)
    )


scrollToKeyboardFocus :
    String
    -> List (Entry a)
    -> Float
    -> ( WithKeyboardFocus a (WithHeights r), Cmd (Msg a), Maybe msg )
    -> ( WithKeyboardFocus a (WithHeights r), Cmd (Msg a), Maybe msg )
scrollToKeyboardFocus id filteredEntries scrollTop ( state, cmd, maybeMsg ) =
    case state.keyboardFocus of
        Just focus ->
            let
                heights =
                    state.heights |> Maybe.withDefault { entries = [], menu = 0 }

                ( top, entryHeight ) =
                    topAndHeight heights.entries filteredEntries (Just focus)

                y =
                    if (top - 2 * entryHeight / 3) < scrollTop then
                        top - 2 * entryHeight / 3
                    else if top + 5 * entryHeight / 3 > (scrollTop + heights.menu) then
                        top + 5 * entryHeight / 3 - heights.menu
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



{- view -}


view :
    ViewConfig a
    -> String
    -> (a -> String)
    -> List (Entry a)
    -> Maybe a
    -> State a
    -> Html (Msg a)
view config id toLabel entries selection state =
    let
        filteredEntries query =
            entries
                |> filter toLabel query

        -- attributes
        containerAttrs attrs =
            attrs ++ noOp config.container

        inputAttrs attrs =
            [ [ Attributes.placeholder
                    (selection
                        |> Maybe.map toLabel
                        |> Maybe.withDefault config.placeholder
                    )
              , Attributes.value state.query
              , Attributes.id (textfieldId id)
              , Events.on "focus" focusDecoder
              ]
            , attrs
            , noOp (config.input (selection /= Nothing) state.open)
            ]
                |> List.concat
    in
    Html.div
        (containerAttrs <|
            if state.open && not (filteredEntries state.query |> List.isEmpty) then
                []
            else
                [ Attributes.style [ ( "overflow", "hidden" ) ] ]
        )
        [ Html.input
            (inputAttrs <|
                if state.open then
                    [ Events.onBlur CloseMenu
                    , Events.on "keyup" keyupDecoder
                    , case state.heights of
                        Nothing ->
                            Events.onWithOptions "keydown" keydownOptions keydownDecoder

                        Just _ ->
                            Events.onWithOptions "keydown" keydownOptions keydownWithoutHeightsDecoder
                    , Events.onInput SetQuery
                    ]
                else
                    []
            )
            []
        , flip Html.Lazy.lazy state.query <|
            \query ->
                Html.div
                    ([ Attributes.id (menuId id)
                     , Events.onMouseDown (PreventClosing True)
                     , Events.onMouseUp (PreventClosing False)
                     ]
                        ++ noOp config.menu
                    )
                    [ filteredEntries query
                        |> List.map
                            (viewEntry toLabel state.open config.entry config.divider state)
                        |> Html.Keyed.ul (noOp config.ul)
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
    Decode.map4
        (\code entryHeights menuHeight scrollTop ->
            case code |> fromCode of
                ArrowUp ->
                    Ok (SetKeyboardFocus Up (Just { entries = entryHeights, menu = menuHeight }) scrollTop)

                ArrowDown ->
                    Ok (SetKeyboardFocus Down (Just { entries = entryHeights, menu = menuHeight }) scrollTop)

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


keydownWithoutHeightsDecoder : Decoder (Msg a)
keydownWithoutHeightsDecoder =
    Decode.map2
        (\code scrollTop ->
            case code |> fromCode of
                ArrowUp ->
                    Ok (SetKeyboardFocus Up Nothing scrollTop)

                ArrowDown ->
                    Ok (SetKeyboardFocus Down Nothing scrollTop)

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
    (a -> String)
    -> Bool
    -> (a -> Bool -> Bool -> HtmlDetails Never)
    -> (String -> HtmlDetails Never)
    -> State a
    -> Entry a
    -> ( String, Html (Msg a) )
viewEntry toLabel open renderEntry renderDivider state entry =
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
    ( case entry of
        Entry entry ->
            toLabel entry

        Divider title ->
            title
    , Html.li
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
    )



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
next entries current =
    -- this is an adaption of the implementation in
    -- thebritican/elm-autocomplete
    entries
        |> List.foldl (getPrevious current) Nothing
        |> Maybe.withDefault current


{-| Return the entry before (i.e. above) the given one, which is not
a `Divider`. Returns the provided entry if there is no previous.
-}
previous : List (Entry a) -> a -> a
previous entries current =
    -- this is an adaption of the implementation in
    -- thebritican/elm-autocomplete
    entries
        |> List.foldr (getPrevious current) Nothing
        |> Maybe.withDefault current


getPrevious : a -> Entry a -> Maybe a -> Maybe a
getPrevious current next result =
    case next of
        Entry nextA ->
            if nextA == current then
                Just nextA
            else if result == Just current then
                Just nextA
            else
                result

        Divider _ ->
            result



{- view helper -}


{-| Compute the distance of the entry to the beginning of the list and
its height, as it is rendered in the DOM.
-}
topAndHeight : List Float -> List (Entry a) -> Maybe a -> ( Float, Float )
topAndHeight entryHeights filteredEntries focus =
    case focus of
        Just a ->
            topAndHeightHelper entryHeights filteredEntries a ( 0, 0 )

        Nothing ->
            ( 0, 0 )


topAndHeightHelper :
    List Float
    -> List (Entry a)
    -> a
    -> ( Float, Float )
    -> ( Float, Float )
topAndHeightHelper entryHeights filteredEntries focus ( distance, height ) =
    case ( entryHeights, filteredEntries ) of
        ( height :: otherHeights, entry :: otherEntries ) ->
            if entry == Entry focus then
                ( distance, height )
            else
                topAndHeightHelper
                    otherHeights
                    otherEntries
                    focus
                    ( distance + height, 0 )

        _ ->
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


scroll : String -> Float -> Cmd (Msg a)
scroll id y =
    Task.attempt (\_ -> NoOp) <|
        Dom.Scroll.toY (menuId id) y


blur : String -> Cmd (Msg a)
blur id =
    Task.attempt (\_ -> NoOp) <|
        Dom.blur (textfieldId id)



{- decoder -}


entryHeightsDecoder : Decoder (List Float)
entryHeightsDecoder =
    DOM.target
        :> DOM.parentElement
        :> DOM.childNode 1
        :> DOM.childNode 0
        :> DOM.childNodes
            (Decode.field "offsetHeight" Decode.float)


menuHeightDecoder : Decoder Float
menuHeightDecoder =
    DOM.target
        :> DOM.parentElement
        :> DOM.childNode 1 (Decode.field "clientHeight" Decode.float)


scrollTopDecoder : Decoder Float
scrollTopDecoder =
    DOM.target
        :> DOM.parentElement
        :> DOM.childNode 1 (Decode.field "scrollTop" Decode.float)


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
