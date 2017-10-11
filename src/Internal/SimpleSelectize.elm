module Internal.SimpleSelectize
    exposing
        ( State
        , closed
        , selection
        , stringUpdate
        , update
        )

import Internal.Entry exposing (Entry)
import Internal.Selectize as Selectize


---- MODEL


type alias State a =
    { menu : Selectize.State a
    , selection : Maybe a
    }


closed : String -> List (Entry a) -> State a
closed id entries =
    { menu = Selectize.closed id entries
    , selection = Nothing
    }


selection : State a -> Maybe a
selection state =
    state.selection



---- UPDATE


type Msg a
    = Select (Maybe a)


stringUpdate :
    State String
    -> Selectize.Msg String
    -> ( State String, Cmd (Selectize.Msg String) )
stringUpdate =
    let
        contains query string =
            string
                |> String.toLower
                |> String.contains
                    (query |> String.toLower)
    in
    update contains


update :
    (String -> a -> Bool)
    -> State a
    -> Selectize.Msg a
    -> ( State a, Cmd (Selectize.Msg a) )
update matches state msg =
    let
        ( newMenu, cmd, maybeMsg ) =
            Selectize.update
                { select = Select
                , matches = matches
                }
                state.selection
                state.menu
                msg

        newState =
            { state | menu = newMenu }
    in
    case maybeMsg of
        Just (Select newSelection) ->
            ( { newState | selection = newSelection }
            , cmd
            )

        Nothing ->
            ( newState
            , cmd
            )
