module TypeChecking exposing (generatedCode, suite)

import Elm
import Elm.Annotation as Type
import Elm.Case
import Elm.Op
import Elm.ToString
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, list, string)
import Internal.Compiler as Compiler
import Internal.Debug as Debug
import Test exposing (..)


successfullyInferredType expression =
    let
        ( _, details ) =
            Compiler.toExpressionDetails Compiler.startIndex expression
    in
    case details.annotation of
        Ok _ ->
            Expect.pass

        Err errs ->
            Expect.fail
                ("Failed to typecheck"
                    ++ String.join "\n"
                        (List.map Compiler.inferenceErrorToString errs)
                )


renderedAs expression str =
    Expect.equal
        (Elm.ToString.expression expression
            |> .body
        )
        str


declarationAs decl str =
    Expect.equal
        (Elm.ToString.declaration decl
            |> .body
        )
        (String.trim str)


importsAs expression str =
    Expect.equal
        (Elm.ToString.expression expression
            |> .imports
        )
        str


suite : Test
suite =
    describe "Type inference!"
        [ test "Strings" <|
            \_ ->
                successfullyInferredType (Elm.string "Hello!")
        , test "Bools" <|
            \_ ->
                successfullyInferredType (Elm.bool True)
        , test "Floats" <|
            \_ ->
                successfullyInferredType (Elm.float 0.6)
        , test "Int" <|
            \_ ->
                successfullyInferredType (Elm.int 6)
        , test "Maybe Bool" <|
            \_ ->
                successfullyInferredType (Elm.maybe (Just (Elm.bool True)))
        , test "List of Records" <|
            \_ ->
                successfullyInferredType
                    (Elm.list
                        [ Elm.record
                            [ Tuple.pair "first" (Elm.int 5)
                            , Tuple.pair "second" (Elm.tuple (Elm.string "hello") (Elm.int 5))
                            , Tuple.pair "first2" (Elm.int 5)
                            , Tuple.pair "second2" (Elm.tuple (Elm.string "hello") (Elm.int 5))
                            , Tuple.pair "first3" (Elm.int 5)
                            , Tuple.pair "second3" (Elm.tuple (Elm.string "hello") (Elm.int 5))
                            ]
                        ]
                    )
        , test "A simple plus function" <|
            \_ ->
                successfullyInferredType
                    (Elm.fn ( "myInt", Nothing ) <|
                        Elm.Op.plus (Elm.int 5)
                    )
        , test "Function with list mapping" <|
            \_ ->
                successfullyInferredType
                    (Elm.fn ( "myArg", Nothing ) <|
                        \myArg ->
                            listMap
                                (\i ->
                                    Elm.Op.plus (Elm.int 5) i
                                )
                                [ myArg
                                ]
                    )
        , test "Function that updates a literal elm record" <|
            \_ ->
                successfullyInferredType
                    (Elm.fn ( "myInt", Nothing ) <|
                        \myInt ->
                            Elm.updateRecord
                                (Elm.record
                                    [ Tuple.pair "first" (Elm.int 5)
                                    , Tuple.pair "second" (Elm.tuple (Elm.string "hello") (Elm.int 5))
                                    , Tuple.pair "first2" (Elm.int 5)
                                    , Tuple.pair "second2" (Elm.tuple (Elm.string "hello") (Elm.int 5))
                                    , Tuple.pair "first3" (Elm.int 5)
                                    , Tuple.pair "second3" (Elm.tuple (Elm.string "hello") (Elm.int 5))
                                    ]
                                )
                                [ Tuple.pair "first" myInt ]
                    )
        , test "Imports are kept when expression is wrapped in letIn" <|
            \_ ->
                importsAs
                    (Elm.letIn [ ( "foo", Elm.unit ) ] <|
                        Elm.value
                            { importFrom = [ "Module" ]
                            , name = "constant"
                            , annotation = Nothing
                            }
                    )
                    "import Module"
        ]



{- HELPERS COPIED FROM GENRATED STUFF

   At some point we should just use the generated stuff directly.

-}


{-| Apply a function to every element of a list.

    map sqrt [ 1, 4, 9 ] == [ 1, 2, 3 ]

    map not [ True, False, True ] == [ False, True, False ]

So `map func [ a, b, c ]` is the same as `[ func a, func b, func c ]`

map: (a -> b) -> List a -> List b

-}
listMap : (Elm.Expression -> Elm.Expression) -> List Elm.Expression -> Elm.Expression
listMap arg arg0 =
    Elm.apply
        (Elm.value
            { importFrom = [ "List" ]
            , name = "map"
            , annotation =
                Just
                    (Type.function
                        [ Type.function [ Type.var "a" ] (Type.var "b")
                        , Type.list (Type.var "a")
                        ]
                        (Type.list (Type.var "b"))
                    )
            }
        )
        [ Elm.functionReduced "unpack" arg, Elm.list arg0 ]



{- Exact output! -}


generatedCode : Test
generatedCode =
    describe "Exact Output"
        [ test "Strings" <|
            \_ ->
                renderedAs
                    (Elm.string "Hello!")
                    "\"Hello!\""
        , test "Function, arg order isn't reversed" <|
            \_ ->
                let
                    exp =
                        Elm.function
                            [ ( "str", Just Type.string )
                            , ( "int", Just Type.int )
                            , ( "bool", Just Type.bool )
                            ]
                            (\args ->
                                case args of
                                    [ one, two, three ] ->
                                        Elm.triple one two three

                                    _ ->
                                        Elm.unit
                            )
                in
                declarationAs
                    (Elm.declaration "myFunc" exp)
                    "myFunc : String -> Int -> Bool -> ( String, Int, Bool )\nmyFunc str int bool =\n    ( str, int, bool )"
        , test "Simplified version of map generates the correct signature" <|
            \_ ->
                declarationAs
                    (Elm.declaration "map" myMap2)
                    """
map : (optional -> fn_result) -> optional -> Optional fn_result
map fn optional =
    Present (fn optional)

"""
        , test "Map function generates corrections " <|
            \_ ->
                Expect.equal
                    (Elm.ToString.expression myMap
                        |> .signature
                    )
                    (String.trim """
(a -> fn_result) -> Optional a -> Optional fn_result
""")
        ]


myMap2 =
    Elm.fn2
        ( "fn", Nothing )
        ( "optional", Nothing )
        (\fn a ->
            present [] (Elm.apply fn [ a ])
        )


myMap =
    Elm.fn2
        ( "fn", Nothing )
        ( "optional", Nothing )
        (\fn optional ->
            Elm.Case.custom optional
                (Type.namedWith [] "Optional" [ Type.var "a" ])
                [ Elm.Case.branch1
                    "Present"
                    ( "present", Type.var "a" )
                    (\a ->
                        let
                            result =
                                present []
                                    (Elm.apply fn [ a ])
                        in
                        result
                    )
                , Elm.Case.branch0 "Null" (null [])
                , Elm.Case.branch0 "Absent" (absent [])
                ]
        )


present : List String -> Elm.Expression -> Elm.Expression
present optionalModuleName a =
    let
        val =
            Elm.apply
                (Elm.value
                    { importFrom = optionalModuleName
                    , name = "Present"
                    , annotation =
                        Just
                            (Type.function [ Type.var "a2" ] (Type.namedWith optionalModuleName "Optional" [ Type.var "a2" ]))

                    -- Nothing
                    }
                )
                [ a ]
    in
    val


null : List String -> Elm.Expression
null optionalModuleName =
    Elm.value
        { importFrom = optionalModuleName
        , name = "Null"
        , annotation = Just (Type.namedWith optionalModuleName "Optional" [ Type.var "a" ])
        }


absent : List String -> Elm.Expression
absent optionalModuleName =
    Elm.value
        { importFrom = []
        , name = "Absent"
        , annotation = Just (Type.namedWith optionalModuleName "Optional" [ Type.var "a" ])
        }
