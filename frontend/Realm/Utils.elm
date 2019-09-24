module Realm.Utils exposing (Field, Form, Rendered(..), edges, err, fi, fieldError, fieldValid, form, formE, html, htmlLine, link, match, matchCtx, matchCtx2, maybeE, maybeS, rendered, renderedE, result, val, yesno, zip)

import Dict exposing (Dict)
import Element as E
import Element.Events as EE
import Html.Parser
import Html.Parser.Util
import Json.Decode as JD
import Json.Encode as JE
import Realm as R


type Rendered
    = Rendered String


rendered : JD.Decoder Rendered
rendered =
    JD.map Rendered JD.string


renderedE : Rendered -> JE.Value
renderedE (Rendered md) =
    JE.string md


html : Rendered -> E.Element (R.Msg msg)
html (Rendered md) =
    case Html.Parser.run md of
        Ok r ->
            Html.Parser.Util.toVirtualDom r
                |> List.map E.html
                |> E.textColumn []

        Err e ->
            E.text (Debug.toString e)


htmlLine : Rendered -> E.Element (R.Msg msg)
htmlLine (Rendered md) =
    case Html.Parser.run md of
        Ok r ->
            Html.Parser.Util.toVirtualDom r
                |> List.map E.html
                |> E.paragraph []

        Err e ->
            E.text (Debug.toString e)


edges : { top : Int, right : Int, bottom : Int, left : Int }
edges =
    { top = 0, right = 0, bottom = 0, left = 0 }


link :
    String
    -> List (E.Attribute msg)
    -> (String -> msg)
    -> E.Element msg
    -> E.Element msg
link url attrs msg label =
    E.link (EE.onClick (msg url) :: attrs) { label = label, url = url }


maybeE : (a -> JE.Value) -> Maybe a -> JE.Value
maybeE fn m =
    case m of
        Just a ->
            fn a

        Nothing ->
            JE.null


maybeS : Maybe String -> JE.Value
maybeS =
    maybeE JE.string


yesno : Bool -> a -> a -> a
yesno y a1 a2 =
    if y then
        a1

    else
        a2


type alias Form =
    Dict String ( String, Maybe String )


formE : Form -> JE.Value
formE =
    JE.dict identity
        (\( v, me ) ->
            let
                jv =
                    JE.string v

                jme =
                    maybeS me
            in
            JE.list identity [ jv, jme ]
        )


form : JD.Decoder Form
form =
    JD.dict (R.tuple JD.string (JD.maybe JD.string))


fieldValid : Field -> Bool
fieldValid f =
    f.value /= "" && f.error == Nothing


type alias Field =
    { value : String
    , error : Maybe String
    , edited : Bool
    }


fi : String -> R.In -> Form -> Field
fi name in_ f =
    let
        v =
            val name in_ f
    in
    { value = v, edited = v /= "", error = err name f }


fieldError : String -> String -> String -> R.In -> Form -> R.TestResult
fieldError tid name error in_ f =
    let
        field =
            fi name in_ f
    in
    if field.error /= Just error then
        R.TestFailed tid <|
            "Expected: "
                ++ error
                ++ ", got: "
                ++ Maybe.withDefault "no error" field.error

    else
        R.TestPassed tid


val : String -> R.In -> Form -> String
val f in_ frm =
    -- server side value precedes hash value
    Dict.get f frm
        |> Maybe.map (\( v, _ ) -> v)
        |> Maybe.withDefault (R.getHash f in_)


err : String -> Form -> Maybe String
err f frm =
    Dict.get f frm
        |> Maybe.andThen (\( _, e ) -> e)


zip : (a -> Maybe b -> c) -> List a -> List b -> List c
zip fn la lb =
    case ( la, lb ) of
        ( a :: ra, b :: rb ) ->
            fn a (Just b) :: zip fn ra rb

        ( a :: ra, [] ) ->
            fn a Nothing :: zip fn ra []

        ( [], _ ) ->
            []


result : JD.Decoder e -> JD.Decoder s -> JD.Decoder (Result e s)
result ed sd =
    JD.oneOf [ JD.field "Err" (JD.map Err ed), JD.field "Ok" (JD.map Ok sd) ]


match : String -> a -> a -> R.TestResult
match tid exp got =
    if exp /= got then
        R.TestFailed tid ("Expected: " ++ Debug.toString exp ++ " got: " ++ Debug.toString got)

    else
        R.TestPassed tid


matchCtx : a -> String -> JD.Decoder a -> JE.Value -> R.TestResult
matchCtx exp key dec v =
    let
        tid =
            "matchCTX." ++ key
    in
    case JD.decodeValue (JD.field key dec) v of
        Ok got ->
            if exp /= got then
                R.TestFailed tid <|
                    "Expected: "
                        ++ Debug.toString exp
                        ++ " got: "
                        ++ Debug.toString got

            else
                R.TestPassed tid

        Err e ->
            R.TestFailed tid (JD.errorToString e)


matchCtx2 : String -> ( String, JD.Decoder a, JE.Value ) -> (a -> Bool) -> R.TestResult
matchCtx2 tid ( key, dec, v ) f =
    case JD.decodeValue (JD.field key dec) v of
        Ok a ->
            if f a then
                R.TestFailed tid "Test Failed"

            else
                R.TestPassed tid

        Err e ->
            R.TestFailed tid (JD.errorToString e)
