module MultiSelectizeAPI exposing (State)

import Selectize.MultiSelectize as Internal


model =
    { menu =
        MultiSelectize.closed "menu-id"
            (\entry -> print entry)
            preSelectedEntries
            allEntries
    }


update msg model =
    case msg of
        MenuMsg menuMsg ->
            let
                ( newMenu, menuCmd ) =
                    MultiSelectize.update
                        { keepQuery = True
                        , textfieldMovable = True
                        }
                        model.menu
                        menuMsg
            in
            ( { model | menu = newMenu }
            , menuCmd |> Cmd.map MenuMsg
            )


view model =
    MultiSelectize.view viewConfig
        model.menu


viewConfig =
    { -- ...
    }



----


model =
    { menu =
        MultiSelectize.closed "menu-id"
            (\entry -> print entry)
            allEntries
    , selectedEntries = preSelectedEntries
    }


update msg model =
    case msg of
        MenuMsg menuMsg ->
            let
                ( newMenu, menuCmd, maybeMsg ) =
                    MultiSelectize.update
                        { select = Select
                        , unselect = Unselect
                        , clearSelection = ClearSelection
                        , keepQuery = True
                        , textfieldMovable = True
                        }
                        model.selectedEntries
                        model.menu
                        menuMsg

                newModel =
                    { model | menu = newMenu }

                cmd =
                    menuCmd |> Cmd.map MenuMsg
            in
            case maybeMsg of
                Just nextMsg ->
                    update nextMsg newModel
                        |> andDo cmd

                Nothing ->
                    ( newModel, cmd )


view model =
    MultiSelectize.view viewConfig
        model.selectedEntries
        model.menu


viewConfig =
    { -- ...
    }



----


type alias State a =
    Internal.State a


closed : String -> List a -> List (Entry a) -> State a
closed id selectedEntries allEntries =
    todo


closedWithRequest : String -> (String -> Task err (List a)) -> State a
closedWithRequest id fetchEntries =
    todo


modelSimple =
    { menu =
        closedWithRequest "menu-id"
            (\_ -> Task.succeed allEntries)
    }


modelHttp =
    { menu =
        closedWithRequest "menu-id"
            (\query ->
                decodeEntries
                    |> Http.get ("/entries/" ++ query)
                    |> Http.send
                    |> Http.toTask
            )
    }


selectedEntries : State a -> List a
selectedEntries state =
    todo


appendEntries : List (Entry a) -> State a -> State a
appendEntries newEntries state =
    todo


type alias Entry a =
    Internal.Entry a


entry : a -> Entry a
entry a =
    Internal.entry a


divider : String -> Entry a
divider title =
    Internal.divider title


type alias Msg a =
    Internal.Msg a


update :
    { keepQuery : Bool
    , textfieldMovable : Bool
    , filter : String -> a -> Bool
    }
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a) )
update config state msg =
    todo


view : ViewConfig a -> State a -> Html (Msg a)
view viewConfig state =
    todo


viewConfig :
    { menu : List (Html.Attribute Never)
    , ul : List (Html.Attribute Never)
    , entry : a -> Bool -> Bool -> HtmlDetails Never
    , divider : String -> HtmlDetails Never
    , toggleButton : Bool -> HtmlDetails Never
    , clearButton : HtmlDetails Never
    , input : Input a
    }
    -> ViewConfig a
viewConfig config =
    todo


simpleInput :
    { container : Bool -> List (Html.Attribute Never)
    , selection : a -> HtmlDetails Action
    , placeholder : Bool -> HtmlDetails Never
    , textfield : Class
    }
simpleInput config =
    todo


type alias Action =
    Internal.Action


unselectOn : String -> Html.Attribute Action
unselectOn event =
    todo


type alias Class =
    String
