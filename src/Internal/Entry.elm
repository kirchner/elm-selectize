module Internal.Entry
    exposing
        ( Entry(..)
        , divider
        , entry
        , selectFirst
        )


type Entry a
    = Entry a
    | Divider String


entry : a -> Entry a
entry a =
    Entry a


divider : String -> Entry a
divider title =
    Divider title


selectFirst : List (Entry a) -> a -> Maybe a
selectFirst entries a =
    case entries of
        [] ->
            Nothing

        first :: rest ->
            case first of
                Entry value ->
                    if a == value then
                        Just a
                    else
                        selectFirst rest a

                _ ->
                    selectFirst rest a
