module Internal.ZipList
    exposing
        ( EntryWithHeight
        , ZipList
        , currentEntry
        , currentHeight
        , first
        , fromList
        , fromListWithFilter
        , next
        , previous
        , removeCurrentEntry
        )

import Internal.Entry exposing (..)


type alias ZipList a =
    { front : List (EntryWithHeight a)
    , current : EntryWithHeight a
    , back : List (EntryWithHeight a)
    , currentTop : Float
    }


type alias EntryWithHeight a =
    ( Entry a, Float )


removeCurrentEntry : ZipList a -> Maybe (ZipList a)
removeCurrentEntry ({ front, current, back, currentTop } as zipList) =
    if back |> containsActualEntries then
        case back of
            [] ->
                Nothing

            next :: rest ->
                { zipList
                    | current = next
                    , back = rest
                }
                    |> first
    else if front |> containsActualEntries then
        case front of
            [] ->
                Nothing

            previous :: rest ->
                let
                    ( _, height ) =
                        previous
                in
                { zipList
                    | front = rest
                    , current = previous
                    , currentTop = currentTop - height
                }
                    |> reverseFirst
    else
        Nothing


containsActualEntries : List (EntryWithHeight a) -> Bool
containsActualEntries entries =
    let
        isActualEntry entry =
            case entry of
                ( Entry _, _ ) ->
                    True

                _ ->
                    False
    in
    entries |> List.any isActualEntry


currentEntry : { r | current : EntryWithHeight a } -> a
currentEntry { current } =
    case current of
        ( Entry a, _ ) ->
            a

        _ ->
            Debug.crash "this should be impossible"


currentHeight : { r | current : EntryWithHeight a } -> Float
currentHeight { current } =
    current |> Tuple.second


fromList : List (Entry a) -> List Float -> Maybe (ZipList a)
fromList entries entryHeights =
    case ( entries, entryHeights ) of
        ( firstEntry :: restEntries, firstHeight :: restHeights ) ->
            { front = []
            , current = ( firstEntry, firstHeight )
            , back = zip restEntries restHeights
            , currentTop = 0
            }
                |> first

        _ ->
            Nothing


fromListWithFilter :
    (String -> a -> Bool)
    -> String
    -> List (Entry a)
    -> List Float
    -> Maybe (ZipList a)
fromListWithFilter matches query entries entryHeights =
    let
        filtered =
            zip entries entryHeights
                |> List.filterMap
                    (\( entry, height ) ->
                        case entry of
                            Entry a ->
                                if a |> matches query then
                                    Just ( Entry a, height )
                                else
                                    Nothing

                            Divider text ->
                                Just ( Divider text, height )
                    )
    in
    case filtered of
        f :: rest ->
            { front = []
            , current = f
            , back = rest
            , currentTop = 0
            }
                |> first

        _ ->
            Nothing


first : ZipList a -> Maybe (ZipList a)
first ({ front, current, back, currentTop } as zipList) =
    case current of
        ( Divider _, _ ) ->
            case back of
                [] ->
                    Nothing

                next :: rest ->
                    { front = current :: front
                    , current = next
                    , back = rest
                    , currentTop = currentTop + Tuple.second current
                    }
                        |> first

        _ ->
            Just zipList


reverseFirst : ZipList a -> Maybe (ZipList a)
reverseFirst ({ front, current, back, currentTop } as zipList) =
    case current of
        ( Divider _, _ ) ->
            case front of
                [] ->
                    Nothing

                previous :: rest ->
                    { front = rest
                    , current = previous
                    , back = current :: back
                    , currentTop = currentTop - Tuple.second previous
                    }
                        |> reverseFirst

        _ ->
            Just zipList


next : ZipList a -> ZipList a
next ({ front, current, back, currentTop } as zipList) =
    case back of
        [] ->
            zipList

        next :: rest ->
            { front = current :: front
            , current = next
            , back = rest
            , currentTop = currentTop + Tuple.second current
            }
                |> first
                |> Maybe.withDefault zipList


previous : ZipList a -> ZipList a
previous ({ front, current, back, currentTop } as zipList) =
    case front of
        [] ->
            zipList

        previous :: rest ->
            { front = rest
            , current = previous
            , back = current :: back
            , currentTop = currentTop - Tuple.second previous
            }
                |> reverseFirst
                |> Maybe.withDefault zipList


moveForwardTo : a -> ZipList a -> ZipList a
moveForwardTo a zipList =
    moveForwardToHelper a zipList
        |> Maybe.withDefault zipList


moveForwardToHelper :
    a
    -> ZipList a
    -> Maybe (ZipList a)
moveForwardToHelper a zipList =
    if (zipList.current |> Tuple.first) == Entry a then
        Just zipList
    else
        case zipList.back of
            [] ->
                Nothing

            _ ->
                zipList
                    |> next
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



---- HELPER


contains : String -> String -> Bool
contains query label =
    label
        |> String.toLower
        |> String.contains (String.toLower query)
