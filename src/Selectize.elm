module Selectize
    exposing
        ( Entry
        , HtmlDetails
        , Msg
        , SharedConfig
        , State
        , UpdateConfig
        , ViewConfig
        , divider
        , empty
        , entry
        , sharedConfig
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
        Selectize.updateConfig sharedConfig
            { select = SelectTree }

    sharedConfig : Selectize.SharedConfig String Model
    sharedConfig =
        Selectize.sharedConfig
            { toLabel = \tree -> tree.name ++ "(" ++ tree.latinName ++ ")"
            , state = \model -> model.menu
            , entries = \model -> model.entries
            , selection = \model -> model.selection
            , id = "tree-menu"
            }

Finally, the menu can be rendered like this

    view : Model -> Html Msg
    view model =
        Html.div []
            [ Selectize.view viewConfig model |> Html.map MenuMsg ]

with the view configuration given by

    viewConfig : Selectize.ViewConfig String Model
    viewConfig =
        Selectize.viewConfig sharedConfig
            { placeholder = "Select a Tree"
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


# Configuration

@docs SharedConfig, sharedConfig, UpdateConfig, updateConfig, ViewConfig, viewConfig


# Update

@docs Msg, update


# View

@docs view, HtmlDetails

-}

import Html exposing (Html)
import Selectize.Selectize as Internal


{- model -}


{-| The internal state of the dropdown menu. This lives in your model.
-}
type alias State a
    = Internal.State a


{-| The initial dropdown state.
-}
empty : State a
empty =
    Internal.empty


{-| Each entry of the menu has to be wrapped in this type. C.f. `entry`
and `divider`.
-}
type alias Entry a
    = Internal.Entry a


{-| Create a selectable `Entry a`.
-}
entry : a -> Entry a
entry a =
    Internal.entry a


{-| Create a divider, which cannot be selected and which is skipped
while traversing the list via arrow up/down keys.
-}
divider : String -> Entry a
divider title =
    Internal.divider title



{- configuration -}


{-| The part of the configuration which is shared by `update` and `view`.
-}
type SharedConfig a model
    = SharedConfig
        { toLabel : a -> String
        , state : model -> State a
        , entries : model -> List (Entry a)
        , selection : model -> Maybe a
        , id : String
        }


{-| Create the shared configuration, for example

    sharedConfig : Selectize.SharedConfig String Model
    sharedConfig =
        Selectize.sharedConfig
            { toLabel = \tree -> tree.name ++ "(" ++ tree.latinName ++ ")"
            , state = .menu
            , entries = .entries
            , selection = .selection
            , id = "tree-menu"
            }

  - `toLabel` should return a unique string representation of `a`.
  - tell the dropdown with `state`, `entries` and `selection` how to
    obtain each of them from the model
  - `id` should be a unique CSS-id for the dropdown (we need this to
    handle focus and blur events correctly)

-}
sharedConfig :
    { toLabel : a -> String
    , state : model -> State a
    , entries : model -> List (Entry a)
    , selection : model -> Maybe a
    , id : String
    }
    -> SharedConfig a model
sharedConfig config =
    SharedConfig
        { toLabel = config.toLabel
        , state = config.state
        , entries = config.entries
        , selection = config.selection
        , id = config.id
        }


{-| The configuration for `Selectize.update`.
-}
type UpdateConfig a msg model
    = UpdateConfig (SharedConfig a model) (Maybe a -> msg)


{-| Create the update configuration, for example

    updateConfig : Selectize.UpdateConfig String Msg Model
    updateConfig =
        Selectize.updateConfig sharedConfig
            { select = SelectTree }

  - tell the dropdown with `select` how we can ask the main application to
    change the selection

-}
updateConfig :
    SharedConfig a model
    -> { select : Maybe a -> msg }
    -> UpdateConfig a msg model
updateConfig sharedConfig config =
    UpdateConfig sharedConfig config.select


{-| The configuration for `Selectize.view`.
-}
type ViewConfig a model
    = ViewConfig (SharedConfig a model) (Internal.ViewConfig a)


{-| Create the view configuration, for example

    viewConfig : Selectize.ViewConfig String Model
    viewConfig =
        Selectize.viewConfig sharedConfig
            { placeholder = "Select a Tree"
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

  - tell us the `placeholder` if the selection is empty
  - `container`, `input`, `toggle`, `menu`, `ul`, `entry` and `divider`
    can be used to style the different parts of the dropdown view, c.f.
    the modul documentation for an example.

-}
viewConfig :
    SharedConfig a model
    ->
        { placeholder : String
        , container : List (Html.Attribute Never)
        , input : Bool -> Bool -> List (Html.Attribute Never)
        , toggle : Bool -> Html Never
        , menu : List (Html.Attribute Never)
        , ul : List (Html.Attribute Never)
        , entry : a -> Bool -> Bool -> HtmlDetails Never
        , divider : String -> HtmlDetails Never
        }
    -> ViewConfig a model
viewConfig sharedConfig config =
    ViewConfig sharedConfig
        { placeholder = config.placeholder
        , container = config.container
        , input = config.input
        , toggle = config.toggle
        , menu = config.menu
        , ul = config.ul
        , entry = config.entry
        , divider = config.divider
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
type alias Msg a
    = Internal.Msg a


{-| The dropdown's update function. C.f. the modul documentation to see
what boilerplate is needed in your main update.
-}
update :
    UpdateConfig a msg model
    -> model
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update (UpdateConfig (SharedConfig sharedConfig) select) model msg =
    let
        ( newState, cmd, maybeMsg ) =
            Internal.update
                sharedConfig.id
                sharedConfig.toLabel
                select
                (sharedConfig.entries model)
                (sharedConfig.selection model)
                (sharedConfig.state model)
                msg
    in
    ( newState, cmd, maybeMsg )



{- view -}


{-| The dropdown's view function.
-}
view : ViewConfig a model -> model -> Html (Msg a)
view (ViewConfig (SharedConfig sharedConfig) viewConfig) model =
    Internal.view viewConfig
        sharedConfig.id
        sharedConfig.toLabel
        (sharedConfig.entries model)
        (sharedConfig.selection model)
        (sharedConfig.state model)
