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


fromList : List (Entry a) -> List Float -> Maybe (ZipList a)
fromList entries entryHeights =
    case ( entries, entryHeights ) of
        ( firstEntry :: restEntries, firstHeight :: restHeights ) ->
            Just
                ({ front = []
                 , current = ( firstEntry, firstHeight )
                 , back = zip restEntries restHeights
                 , currentTop = 0
                 }
                    |> zipFirst
                )

        _ ->
            Nothing


fromListWithFilter :
    (a -> Bool)
    -> List (Entry a)
    -> List Float
    -> Maybe (ZipList a)
fromListWithFilter keep entries entryHeights =
    let
        filtered =
            zip entries entryHeights
                |> List.filter
                    (\( entry, height ) ->
                        case entry of
                            Entry a ->
                                keep a

                            Divider _ ->
                                True
                    )
    in
    case filtered of
        first :: rest ->
            Just
                ({ front = []
                 , current = first
                 , back = rest
                 , currentTop = 0
                 }
                    |> zipFirst
                )

        _ ->
            Nothing


zipFirst : ZipList a -> ZipList a
zipFirst zipList =
    case zipList.current of
        ( Divider _, _ ) ->
            case zipList.back of
                [] ->
                    zipList

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
            zipList


zipReverseFirst : ZipList a -> ZipList a
zipReverseFirst zipList =
    case zipList.current of
        ( Divider _, _ ) ->
            case zipList.front of
                [] ->
                    zipList

                previous :: rest ->
                    zipReverseFirst
                        { front = rest
                        , current = previous
                        , back = zipList.current :: zipList.back
                        , currentTop =
                            zipList.currentTop
                                - Tuple.second zipList.current
                        }

        _ ->
            zipList


zipNext : ZipList a -> ZipList a
zipNext zipList =
    case zipList.back of
        [] ->
            zipList

        next :: rest ->
            zipFirst
                { front = zipList.current :: zipList.front
                , current = next
                , back = rest
                , currentTop =
                    zipList.currentTop
                        + Tuple.second zipList.current
                }


zipPrevious : ZipList a -> ZipList a
zipPrevious zipList =
    case zipList.front of
        [] ->
            zipList

        previous :: rest ->
            zipReverseFirst
                { front = rest
                , current = previous
                , back = zipList.current :: zipList.back
                , currentTop =
                    zipList.currentTop
                        - Tuple.second zipList.current
                }


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



---- MODEL


type alias State a =
    { query : String
    , zipList : Maybe (ZipList a)
    , filteredEntries : Maybe (List (Entry a))
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


empty : State a
empty =
    { query = ""
    , zipList = Nothing
    , filteredEntries = Nothing
    , mouseFocus = Nothing
    , preventBlur = False
    , open = False
    , entryHeights = []
    , menuHeight = 0
    , scrollTop = 0
    }



---- CONFIGURATION


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



---- UPDATE


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
    | SetKeyboardFocus Movement Float
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
                zipList =
                    fromList entries heights.entries
                        |> Maybe.map
                            (case selection of
                                Just a ->
                                    moveForwardTo a

                                Nothing ->
                                    identity
                            )

                top =
                    zipList
                        |> Maybe.map zipCurrentScrollTop
                        |> Maybe.withDefault 0

                height =
                    zipList
                        |> Maybe.map zipCurrentHeight
                        |> Maybe.withDefault 0
            in
            ( { state
                | zipList = zipList
                , filteredEntries = Just entries
                , mouseFocus = Nothing
                , query = ""
                , open = True
                , entryHeights = heights.entries
                , menuHeight = heights.menu
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
            let
                newZipList =
                    fromListWithFilter keep entries state.entryHeights

                keep entry =
                    toLabel entry
                        |> String.toLower
                        |> String.contains (String.toLower newQuery)

                newFilteredEntries =
                    entries
                        |> filter toLabel newQuery
            in
            ( { state
                | query = newQuery
                , zipList = newZipList
                , filteredEntries = Just newFilteredEntries
                , mouseFocus = Nothing
              }
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

        SetKeyboardFocus movement scrollTop ->
            state
                |> updateKeyboardFocus select movement
                |> scrollToKeyboardFocus id scrollTop

        SelectKeyboardFocusAndBlur ->
            ( state |> reset
            , blur id
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
                    if (top - 2 * height / 3) < scrollTop then
                        top - 2 * height / 3
                    else if
                        (top + 5 * height / 3)
                            > (scrollTop + state.menuHeight)
                    then
                        top + 5 * height / 3 - state.menuHeight
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
    -> String
    -> (a -> String)
    -> List (Entry a)
    -> Maybe a
    -> State a
    -> Html (Msg a)
view config id toLabel entries selection state =
    let
        actualEntries =
            state.filteredEntries
                |> Maybe.withDefault entries

        keyboardFocus =
            state.zipList |> Maybe.map currentEntry

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
            if state.open && not (actualEntries |> List.isEmpty) then
                []
            else
                [ Attributes.style [ ( "overflow", "hidden" ) ] ]
        )
        [ Html.input
            (inputAttrs <|
                if state.open then
                    [ Events.onBlur CloseMenu
                    , Events.on "keyup" keyupDecoder
                    , Events.onWithOptions "keydown" keydownOptions keydownDecoder
                    , Events.onInput SetQuery
                    ]
                else
                    []
            )
            []
        , Html.div
            ([ Attributes.id (menuId id)
             , Events.onMouseDown (PreventClosing True)
             , Events.onMouseUp (PreventClosing False)
             ]
                ++ noOp config.menu
            )
            [ actualEntries
                |> List.map
                    (viewEntry
                        toLabel
                        state.open
                        config.entry
                        config.divider
                        keyboardFocus
                        state.mouseFocus
                    )
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
    (a -> String)
    -> Bool
    -> (a -> Bool -> Bool -> HtmlDetails Never)
    -> (String -> HtmlDetails Never)
    -> Maybe a
    -> Maybe a
    -> Entry a
    -> ( String, Html (Msg a) )
viewEntry toLabel open renderEntry renderDivider keyboardFocus mouseFocus entry =
    let
        { attributes, children } =
            case entry of
                Entry entry ->
                    renderEntry entry
                        (mouseFocus == Just entry)
                        (keyboardFocus == Just entry)

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



---- HELPER


{-| Return all entries which contain the given query. Return the whole
list if the query equals `""`.
-}
filter :
    (a -> String)
    -> String
    -> List (Entry a)
    -> List (Entry a)
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


blur : String -> Cmd (Msg a)
blur id =
    Task.attempt (\_ -> NoOp) <|
        Dom.blur (textfieldId id)



---- DECODER


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
