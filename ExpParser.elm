module ExpParser where

import Char
import Maybe exposing (withDefault)
import Result exposing (toMaybe)
import String
import Array as A

import Expression exposing (..)
import OurParser as P exposing (Parser, (*>))

-- switch to haskell syntax
(+++) = P.or
(<++) = P.left_or
(<$>) = P.map
(>>=) = P.andThen

--the following part is copied from the Parser.Number library

--TODO : copy other functions from the Parser.Number library and Parser.Char library
digit : Parser Int
digit =
    let
        charToInt c = Char.toCode c - Char.toCode '0'
    in
        P.map charToInt (P.satisfy Char.isDigit)

{-| Parse a natural number -}
natural : Parser Int
natural =
    P.some digit
    |> P.map (List.foldl (\b a -> a * 10 + b) 0)

{-| Parse a optional sign, succeeds with a -1 if it matches a minus `Char`, otherwise it returns 1 -}
sign : Parser Int
sign =
    let
        plus =
            P.map (always -1) (P.symbol '-')
        min =
            P.map (always 1) (P.symbol '+')
    in
        P.optional (plus `P.or` min) 1

{-| Parse an integer with optional sign -}
integer : Parser Int
integer =
    P.map (*) sign
    |> P.andMap natural

{-| The fromOk function extracts the element out of a Ok, with a default. -}
fromOk : a -> Result e a -> a
fromOk default result =
    withDefault default (toMaybe result)
                
{-| Parse a float with optional sign -}
float : Parser Float
float =
    let
        toFloatString (i, ds) =
          toString i ++ "." ++ String.concat (List.map toString ds)
        convertToFloat sig int digs =
          toFloat sig * (fromOk 0.0 << String.toFloat << toFloatString) (int, digs)
    in
        P.map convertToFloat sign
        |> P.andMap integer
        |> P.andMap (P.symbol '.' *> P.some digit)

--------------------------------------------------------------

--TODO:
-- clean up unnecessary code
-- include the parser for float
-- expand parseExp to include all Ops

fromOk_ : Result String a -> a
fromOk_ mx =
  case mx of
    Ok a -> a
    Err s -> Debug.crash <| "fromOk_: " ++ s
             
isAlphaNum : Char -> Bool
isAlphaNum c = Char.isUpper c || Char.isLower c || Char.isDigit c

isLetter : Char -> Bool
isLetter c = Char.isUpper c || Char.isLower c

isSpace : Char -> Bool
isSpace c = c == ' ' || c == '\t' || c == '\n'
            
intOrFloat : Parser Float
intOrFloat = float <++ (toFloat <$> integer)
             
token1 : a -> String -> Parser a
token1 val str = skipSpaces *> (always val <$> P.token str)

parseReal : Parser Exp
parseReal = skipSpaces *> (EReal <$> intOrFloat)
            
parseComplex : Parser Exp
parseComplex =
  skipSpaces *>
  intOrFloat >>= \a ->
  P.token "+" *>
  skipSpaces  *>
  intOrFloat >>= \b ->
  P.token "i" *>
  P.succeed (EComplex {re = a, im = b})

parseNum : Parser Exp
parseNum = parseComplex <++ parseReal
             
skipSpaces : Parser ()
skipSpaces = P.map (\_ -> ()) <| P.many <| P.satisfy isSpace

parens : Parser a -> Parser a
parens p =
  P.between (skipSpaces *> P.token "(") (skipSpaces *> P.token ")") p

comma = P.satisfy ((==) ',')
left_curly = P.satisfy ((==) '{')
right_curly = P.satisfy ((==) '}')

maybeParens : Parser a -> Parser a
maybeParens p =
  P.between (skipSpaces *> (P.optional1 <| P.token "(")) (skipSpaces *> (P.optional1 <| P.token ")")) p
                                                                     
parseConst : Parser Exp
parseConst =
     (token1 (EConst Pi) "pi")
 <++ (token1 (EConst E) "e")

parseUOp : Parser (Exp -> Exp)
parseUOp = skipSpaces *>
  ((token1 (EUnaryOp Sin) "sin")
  <++ (token1 (EUnaryOp Cos) "cos")
  <++ (token1 (EUnaryOp Tan) "tan")
  <++ (token1 (EUnaryOp ArcSin) "arcsin")
  <++ (token1 (EUnaryOp ArcTan) "arctan")
  <++ (token1 (EUnaryOp ArcCos) "arccos")
  <++ (token1 (EUnaryOp Floor) "floor")
  <++ (token1 (EUnaryOp Ceiling) "ceiling")
  <++ (token1 (EUnaryOp Round) "round")
  <++ (token1 (EUnaryOp Sqrt) "sqrt")
  <++ (token1 (EUnaryOp Re) "re")
  <++ (token1 (EUnaryOp Im) "im")
  <++ (token1 (EUnaryOp Abs) "abs")
  <++ (token1 (EUnaryOp Det) "det")
  <++ (token1 (EUnaryOp EigenValue) "eigenvalue")
  <++ (token1 (EUnaryOp EigenVector) "eigenvector")
  <++ (token1 (EUnaryOp Solve) "solve")
  <++ (token1 (EUnaryOp Inv) "inv"))

parseMatrix : Parser Exp
parseMatrix =
  P.recursively <| \_ ->
    skipSpaces *>
    (P.map EMatrix <|
     P.between left_curly right_curly <|
      P.map A.fromList <| P.separatedBy parseVector comma)

parseVector : Parser (Vector Exp)
parseVector =
  P.recursively <| \_ ->
    skipSpaces *>
    (P.between left_curly right_curly <|
     P.map A.fromList <| P.separatedBy parseExp comma)

parseFun : Parser Exp
parseFun =
  P.recursively <| \_ ->
    parseVar >>= \name ->
      parens (P.separatedBy parseVar (skipSpaces *> comma)) >>= \vars ->
        skipSpaces *>
        P.satisfy ((==) '=') *>
        parseExp >>= \e ->
          P.succeed <| EFun name vars e
                            
parseVar : Parser Var
parseVar =
  let pred x = isAlphaNum x && not (isSpace x) in
  skipSpaces *>
  P.some (P.satisfy pred) >>= \s ->
    case s of
      [] -> Debug.crash "impossible"
      c :: cs -> if isLetter c then
                   if List.any (flip String.contains (String.fromList s)) allOps then P.empty
                   else P.succeed <| String.fromList s
                 else P.empty

parseEVar : Parser Exp
parseEVar = EVar <$> parseVar

allOps : List String
allOps =
  [ "pi","e"
  ,"sin", "cos", "tan", "arcsin", "arccos", "arctan", "floor","ceiling","round","sqrt","log"
  , "+","-","*","/"
  , "det","eigenvalue","eigenvector","inv","solve"
  ]

opStr : String -> Op
opStr s =
  case s of
    "pi" -> Pi
    "e"  -> E
    "sin" -> Sin
    "cos" -> Cos
    "tan" -> Tan
    "arcsin" -> ArcSin
    "arccos" -> ArcCos
    "arctan" -> ArcTan
    "floor" -> Floor
    "ceiling" -> Ceiling
    "round" -> Round
    "sqrt" -> Sqrt
    "log" -> Log
    "+" -> Plus
    "-" -> Minus
    "*" -> Mult
    "/" -> Frac
    _ -> Debug.crash <| "opStr: " ++ s

strOp : Op -> String
strOp op =
  case op of
    Pi -> "pi"
    E  -> "e"
    Sin -> "sin"
    Cos -> "cos"
    Tan -> "tan"
    ArcSin -> "arcsin"
    ArcCos -> "arccos"
    ArcTan -> "arctan"
    Floor -> "floor"
    Ceiling -> "ceiling"
    Round -> "round"
    Sqrt -> "sqrt"
    Log  -> "log"
    Plus -> "+"
    Minus -> "-"
    Mult -> "*"
    Frac -> "/"
    Pow  -> "^"
    Mod  -> "mod"
    _  -> Debug.crash <| "strOp: " ++ toString op

--parse and unparse based on http://cmsc-16100.cs.uchicago.edu/2015/Lectures/23-propositional-logic-parsing.php

parseExp : Parser Exp
parseExp = P.recursively <| \_ ->
   let  prec0 = P.recursively <| \_ -> P.chainl1 prec1 <|
                (token1 (EBinaryOp Plus) "+")
                 <++ (token1 (EBinaryOp Minus) "-")
        prec1 = P.recursively <| \_ -> P.chainl1 prec2 <|
                (token1 (EBinaryOp Mult) "*")
                <++ (token1 (EBinaryOp Frac) "/")  
        prec2 = P.recursively <| \_ -> P.chainl1 prec3 <|
                (token1 (EBinaryOp Pow) "^")
                <++ (token1 (EBinaryOp Mod) "%")
        prec3 = P.recursively <| \_ -> P.prefix prec4 parseUOp
        prec4 = P.recursively <| \_ ->
                parseFun
                <++ parseEVar
                <++ parseMatrix
                <++ parseNum
                <++ parens prec0
                --<++ parseConst
   in prec0

parse : String -> Result String Exp
parse s = P.parse parseExp s

unparse : Exp -> String
unparse = prec 0

matrixRender : String -> String
matrixRender s = "\\begin{pmatrix}" ++ s ++ "\\end{pmatrix}"

vec : Vector Exp -> String
vec v = (String.concat <| List.intersperse " & " <| A.toList <| A.map unparse v) ++ "\\\\"
        
unparseVec : Vector Exp -> String
unparseVec = matrixRender << vec

unparseMatrix : Matrix Exp -> String
unparseMatrix = matrixRender << String.concat << A.toList << A.map vec
      
prec i e =
  case e of
    EReal x -> toString x
    EComplex x -> if x.im == 0 then toString x.re
                  else toString x.re ++ "+" ++ toString x.im ++ "i"
    EVector v -> unparseVec v
    EMatrix m -> unparseMatrix m
    EUnaryOp op e1 -> strOp op ++ prec 4 e1
    EBinaryOp op e1 e2 ->
      let toPrec n = paren n i <| prec n e1 ++ strOp op ++ prec n e2 in
      case op of
        Plus -> toPrec 1
        Minus -> toPrec 1
        Mult -> toPrec 2
        Frac -> toPrec 2
        Pow -> toPrec 3
        Mod -> toPrec 3
        _   -> Debug.crash "prec: not a binary op"
    _ -> Debug.crash <| toString e
         
paren cutoff prec str =
  if prec > cutoff then "(" ++ str ++ ")"
  else str
  
test1 = P.parse parseExp "sin(2+3i)"

test2 = unparseMatrix (A.fromList [A.fromList [EReal 1,EReal 2],A.fromList [EReal 3,EReal 4]])
