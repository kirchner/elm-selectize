module Selectize
    exposing
        ( Entry
        , HtmlDetails
        , Input
        , Msg
        , State
        , ViewConfig
        , autocomplete
        , closed
        , divider
        , entry
        , simple
        , update
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
        }

    type alias Tree =
        { name : String
        , latinName : String
        }

The state of the dropdown menu is instanciated via

    menu =
        Selectize.closed "unique-menu-id"
            (\tree -> tree.name ++ " - " ++ tree.latinName)
            (trees |> List.map Selectize.entry)

with

    trees : List Tree

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
                        Selectize.update SelectTree
                            model.selection
                            model.menu
                            selectizeMsg

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

Finally, the menu can be rendered like this

    view : Model -> Html Msg
    view model =
        Html.div []
            [ Selectize.view viewConfig
                model.selection
                model.menu
                |> Html.map MenuMsg
            ]

with the view configuration given by

    viewConfig : Selectize.ViewConfig String
    viewConfig =
        Selectize.viewConfig
            { placeholder = "Select a Tree"
            , container =
                [ Attributes.class "selectize__container" ]
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
            , input = styledInput
            }

and a selector given by, for example,

    styledInput : Selectize.selector Tree
    styledInput =
        Selectize.autocomplete <|
            \sthSelected open ->
                [ Attributes.class "selectize__textfield"
                , Attributes.classList
                    [ ( "selectize__textfield--selection", sthSelected )
                    , ( "selectize__textfield--no-selection", not sthSelected )
                    , ( "selectize__textfield--menu-open", open )
                    ]
                ]


# Types

@docs State, closed, Entry, entry, divider


# Update

@docs Msg, update


# View

@docs view, ViewConfig, viewConfig, HtmlDetails, Input, simple, autocomplete

-}

import Html exposing (Html)
import Html.Lazy as Lazy
import Selectize.Selectize as Internal


{- model -}


{-| The internal state of the dropdown menu. This lives in your model.
-}
type alias State a =
    Internal.State a


{-| Use this function to initialize your dropdown menu, for example by

    menu =
        Selectize.closed "unique-menu-id"
            entryToLabel
            entries

It will have the provided entries and be closed. The provided id should
be unique. If for some reason the entries change, just reinstantiate
your dropdown state with this function.

-}
closed :
    String
    -> (a -> String)
    -> List (Entry a)
    -> State a
closed id toLabel entries =
    Internal.closed id toLabel entries


{-| Each entry of the menu has to be wrapped in this type. We need this,
as an entry can either be selectable (and therefore also focusable) or
not. You can construct these using `entry` and `divider`.
-}
type alias Entry a =
    Internal.Entry a


{-| Create a selectable `Entry a`.
-}
entry : a -> Entry a
entry a =
    Internal.entry a


{-| Create a divider, which can neither be selected nor focused. It
is therefore skipped while traversing the list via up/down keys.
-}
divider : String -> Entry a
divider title =
    Internal.divider title



{- configuration -}


{-| The configuration for `Selectize.view`.
-}
type alias ViewConfig a =
    Internal.ViewConfig a


{-| Create the view configuration, for example

    viewConfig : Selectize.ViewConfig String
    viewConfig =
        Selectize.viewConfig
            { container = [ ... ]
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
            , input = someInput
            }

  - `container`, `menu`, `ul`, `entry` and `divider` can be
    used to style the different parts of the dropdown view, c.f. the
    modul documentation for an example.
  - with `input` you can choose if you want autocompletion or just
    a simple dropdown menu, you can choose for example
    `Selectize.simple` or `Selectize.autocomplete`.

-}
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


{-| `entry` and `divider` should return this.
-}
type alias HtmlDetails msg =
    { attributes : List (Html.Attribute msg)
    , children : List (Html msg)
    }



{- update -}


{-| The dropdown menu produces these messages.
-}
type alias Msg a =
    Internal.Msg a


{-| The dropdown's update function. Take a look at the beginning of this
module documentation to see what boilerplate is needed in your main
update.
-}
update :
    (Maybe a -> msg)
    -> Maybe a
    -> State a
    -> Msg a
    -> ( State a, Cmd (Msg a), Maybe msg )
update select selection state msg =
    Internal.update select selection state msg



{- view -}


{-| The dropdown's view function. You have to provide the current
selection (along with the configuration and the its actual state).
-}
view : ViewConfig a -> Maybe a -> State a -> Html (Msg a)
view viewConfig selection state =
    Lazy.lazy3 Internal.view viewConfig selection state


{-| You have to choose a `Selector` in your view configuration. This
decides if you have a simple dropdown or an autocompletion version.
-}
type alias Input a =
    Internal.Input a


{-| An input for displaying a simple dropdown.

  - `attrs = \sthSelected open -> [ ... ]` is used to style the actual
    button
  - you can style optional buttons via `toggleButton` and `clearButton`,
    for example `toggleButton = Just (\open -> Html.div [ ... ] [ ... ])`
  - tell us the `placeholder` if the selection is empty

-}
simple :
    { attrs : Bool -> Bool -> List (Html.Attribute Never)
    , toggleButton : Maybe (Bool -> Html Never)
    , clearButton : Maybe (Html Never)
    , placeholder : String
    }
    -> Input a
simple config =
    Internal.simple config


{-| An input for an autocompletion dropdown.

  - `attrs = \sthSelected open -> [ ... ]` is used to style the actual
    textfield (You probably need to overwrite the placeholder styling,
    see the source code of the demo for an example stylesheet.)
  - you can style optional buttons via `toggleButton` and `clearButton`,
    for example `toggleButton = Just (\open -> Html.div [ ... ] [ ... ])`
  - tell us the `placeholder` if the selection is empty

-}
autocomplete :
    { attrs : Bool -> Bool -> List (Html.Attribute Never)
    , toggleButton : Maybe (Bool -> Html Never)
    , clearButton : Maybe (Html Never)
    , placeholder : String
    }
    -> Input a
autocomplete config =
    Internal.autocomplete config
