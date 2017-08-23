module TestRunner exposing (main)

import Test exposing (concat)
import Test.Runner.Html
import Tests
import ArchitectureTests


main : Test.Runner.Html.TestProgram
main =
    [ Tests.suite
    , ArchitectureTests.suite
    ]
        |> concat
        |> Test.Runner.Html.run
