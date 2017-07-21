module Selectize
    exposing
        ( Entry
        , HtmlDetails
        , Msg
        , State
        , UpdateConfig
        , ViewConfig
        , divider
        , empty
        , entry
        , update
        , updateConfig
        , view
        , viewConfig
        )

{-| This is a dropdown menu whose entries can be filtered. You can
select entries using the mouse or with the keyboard (arrow up/down and
enter).

The dropdown menu manages the keyboard and mouse focus, as well as the
open/closed state itself. The (unfiltered) list of possible entries and
the eventually selected entry have to live in the model of the
actual application.

If you want to use it, your model should look something like this

    type alias Model =
        { selection : Maybe Tree
        , menu : Selectize.State Tree
        , entries : List (Selectize.Entry Tree)
        }

    type alias Tree =
        { name : String
        , latinName : String
        }

And you have to hook it up in your update function like so

    type Msg
        = MenuMsg (Selectize.Msg Tree)
        | SelectTree (Maybe Tree)

    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            MenuMsg selectizeMsg ->
                let
                    ( newMenu, menuCmd, maybeMsg ) =
                        Selectize.update updateConfig model selectizeMsg

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

            SelectTree newSelection ->
                ( { model | selection = newSelection }, Cmd.none )

    andDo : Cmd msg -> ( model, Cmd msg ) -> ( model, Cmd msg )
    andDo cmd ( model, cmds ) =
        ( model
        , Cmd.batch [ cmd, cmds ]
        )

where the update configuration is given by

    updateConfig : Selectize.UpdateConfig String Msg Model
    updateConfig =
        Selectize.updateConfig
            { toLabel = \tree -> tree.name ++ "(" ++ tree.latinName ++ ")"
            , state = \model -> model.menu
            , entries = \model -> model.entries
            , selection = \model -> model.selection
            , id = "tree-menu"
            , select = SelectTree
            }

Finally, the menu can be rendered like this

    view : Model -> Html Msg
    view model =
        Html.div []
            [ Selectize.view viewConfig model |> Html.map MenuMsg ]

with the view configuration given by

    viewConfig : Selectize.ViewConfig String Model
    viewConfig =
        Selectize.viewConfig
            { toLabel = \tree -> tree.name ++ "(" ++ tree.latinName ++ ")"
            , state = \model -> model.menu
            , entries = \model -> model.entries
            , selection = \model -> model.selection
            , id = "tree-menu"
            , placeholder = "Select a Tree"
            , container =
                [ Attributes.class "selectize__container" ]
            , input =
                \sthSelected open ->
                    [ Attributes.class "selectize__textfield"
                    , Attributes.classList
                        [ ( "selectize__textfield--selection", sthSelected )
                        , ( "selectize__textfield--no-selection", not sthSelected )
                        , ( "selectize__textfield--menu-open", open )
                        ]
                    ]
            , toggle =
                \open ->
                    Html.div
                        [ Attributes.class "selectize__menu-toggle"
                        , Attributes.classList
                            [ ( "selectize__menu-toggle--menu-open", open ) ]
                        ]
                        [ Html.i
                            [ Attributes.class "material-icons"
                            , Attributes.class "selectize__icon"
                            ]
                            [ if open then
                                Html.text "arrow_drop_up"
                              else
                                Html.text "arrow_drop_down"
                            ]
                        ]
            , menu =
                [ Attributes.class "selectize__menu" ]
            , ul =
                [ Attributes.class "selectize__list" ]
            , entry =
                \tree mouseFocused keyboardFocused ->
                    { attributes =
                        [ Attributes.class "selectize__item"
                        , Attributes.classList
                            [ ( "selectize__item--mouse-selected"
                              , mouseFocused
                              )
                            , ( "selectize__item--key-selected"
                              , keyboardFocused
                              )
                            ]
                        ]
                    , children =
                        [ Html.text tree ]
                    }
            , divider =
                \title ->
                    { attributes =
                        [ Attributes.class "selectize__divider" ]
                    , children =
                        [ Html.text title ]
                    }
            }


# Types

@docs State, empty, Entry, entry, divider


# Update

@docs Msg, update, UpdateConfig, updateConfig


# View

@docs view, ViewConfig, viewConfig, HtmlDetails

-}

import Html exposing (Html)
import Selectize.Selectize as Internal


{- model -}


{-| The internal state of the dropdown menu. This lives in your model.
-}
type State a
    = State (Internal.State a)


{-| The initial dropdown state.
-}
empty : State a
empty =
    State Internal.empty


{-| Each entry of the menu has to be wrapped in this type. C.f. `entry`
and `divider`.
-}
type Entry a
    = Entry (Internal.Entry a)


{-| Create a selectable `Entry a`.
-}
entry : a -> Entry a
entry a =
    Entry (Internal.entry a)


{-| Create a divider, which cannot be selected and which is skipped
while traversing the list via arrow up/down keys.
-}
divider : String -> Entry a
divider title =
    Entry (Internal.divider title)



{- configuration -}


{-| The configuration for `Selectize.update`.
-}
type UpdateConfig a msg model
    = UpdateConfig (Internal.UpdateConfig a msg model)


{-| Create the update configuration, for example

    updateConfig : Selectize.UpdateConfig String Msg Model
    updateConfig =
        Selectize.updateConfig
            { toLabel = \tree -> tree.name ++ "(" ++ tree.latinName ++ ")"
            , state = .menu
            , entries = .entries
            , selection = .selection
            , id = "tree-menu"
            , select = SelectTree
            }

  - `toLabel` should return a unique string representation of `a`.
  - tell the dropdown with `state`, `entries` and `selection` how to
    obtain each of them from the model
  - `id` should be a unique CSS-id for the dropdown (we need this to
    handle focus and blur events correctly)
  - tell the dropdown with `select` how we can ask the main application to
    change the selection

-}
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
    UpdateConfig <|
        Internal.updateConfig
            { config
                | state =
                    \model ->
                        case config.state model of
                            State state ->
                                state
                , entries =
                    \model ->
                        config.entries model
                            |> List.map (\(Entry entry) -> entry)
            }


{-| The configuration for `Selectize.view`.
-}
type ViewConfig a model
    = ViewConfig (Internal.ViewConfig a model)


{-| Create the view configuration, for example

    viewConfig : Selectize.ViewConfig String Model
    viewConfig =
        Selectize.viewConfig
            { toLabel = \tree -> tree.name ++ "(" ++ tree.latinName ++ ")"
            , state = .menu
            , entries = .entries
            , selection = .selection
            , id = "tree-menu"
            , placeholder = "Select a Tree"
            , container = [ ... ]
            , input =
                \sthSelected open -> [ ... ]
            , toggle =
                \open ->
                    Html.div
                        ...
            , menu = [ ... ]
            , ul = [ ... ]
            , entry =
                \tree mouseFocused keyboardFocused ->
                    { attributes = ...
                    , children = ...
                    }
            , divider =
                \title ->
                    { attributes = ...
                    , children = ...
                    }
            }

  - `toLabel`, `state`, `entries`, `selection` and `id` have to be the
    same as in the `updateConfig`
  - tell us the `placeholder` if the selection is empty
  - `container`, `input`, `toggle`, `menu`, `ul`, `entry` and `divider`
    can be used to style the different parts of the dropdown view, c.f.
    the modul documentation for an example.

-}
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
    ViewConfig <|
        Internal.viewConfig
            { config
                | state =
                    \model ->
                        case config.state model of
                            State state ->
                                state
                , entries =
                    \model ->
                        config.entries model
                            |> List.map (\(Entry entry) -> entry)
            }


{-| `entry` and `divider` should return this.
-}
type alias HtmlDetails msg =
    { attributes : List (Html.Attribute msg)
    , children : List (Html msg)
    }



{- update -}


{-| The dropdown menu produces these messages.
-}
type Msg a
    = Msg (Internal.Msg a)


{-| The dropdown's update function. C.f. the modul documentation for an
example how to hook it into your main update.
-}
update :
    UpdateConfig a msg model
    -> model
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update (UpdateConfig config) model (Msg msg) =
    let
        ( newState, cmd, maybeMsg ) =
            Internal.update config model msg
    in
    ( State newState, cmd |> Cmd.map Msg, maybeMsg )



{- view -}


{-| The dropdown's view function.
-}
view : ViewConfig a model -> model -> Html (Msg a)
view (ViewConfig config) model =
    Internal.view config model
        |> Html.map Msg
