--- Full-featured argument parser
--- Bart Massey 2007/01/06
---
--- Copyright (C) 2007 Bart Massey
--- ALL RIGHTS RESERVED

module ParseArgs (Argtype(..), DataArg(..), Arg(..),
                  ArgVal(..), Args(..),
                  ArgsComplete(..),
                  baseName, parseArgs)
where

import Data.List
import qualified Data.Map as Map
import Control.Monad
import System.IO
import Data.Maybe
import System.Environment

--- The main job of this module is to provide parseArgs.
--- See below for its contract.

---
--- provided datatypes
---

--- The types of arguments carrying data
data Argtype = ArgtypeString | ArgtypeInt

--- Information specific to an argument carrying data
data DataArg = DataArg { dataArgName :: String,
                         dataArgArgtype :: Argtype,
                         dataArgOptional :: Bool }

--- The description of an argument, suitable for
--- messages and for parsing.
---
--- XXX ugly representation
--- There are three cases:
---     1) The argument is a flag, in which case at least
---     one of argAbbr and argName is provided.
---        1.1) The flag itself requires an argument, in
---        which case argData is also provided.
---     2) The argument is positional, in which case neither
---     argAbbr nor argName are provided, but argData is
---     provided.
--- If none of argAbbr, argName, argData are provided, this
--- is an error.
--- In case 1.1 or 2, the dataArgOptional field of
--- argData determines whether the given flag or
--- positional argument must appear.  Obviously, all
--- flags are optional.

data (Ord a) => Arg a =
    Arg { argIndex :: a,
          argAbbr :: Maybe Char,
          argName :: Maybe String,
          argData :: Maybe DataArg,
          argDesc :: String }

---
--- returned datatypes
---

--- The kinds of "value" an argument can have.
data ArgVal =
    ArgValFlag |
    ArgValString String |
    ArgValInt Int

--- The data structure parseArgs produces.
data (Ord a) => Args a =
    Args { args :: Map.Map a ArgVal,
           argsProgName :: String,
           argsUsage :: String,
           argsRest :: [ String ] }

---
--- Implementation
---

--- Return the filename part of 'path'.
--- Unnecessarily efficient implementation does a single
--- tail-call traversal with no construction.
baseName :: String -> String
baseName s =
    let s' = dropWhile (/= '/') s in
    if null s' then s else baseName (tail s')


--- True if the described argument is positional
arg_posn :: (Ord a) => Arg a -> Bool
arg_posn (Arg { argAbbr = Nothing,
                argName = Nothing }) = True
arg_posn _ = False

--- True if the described argument is a flag
arg_flag :: (Ord a) => Arg a -> Bool
arg_flag a = not (arg_posn a)

--- True if the described argument is optional
arg_optional :: (Ord a) => Arg a -> Bool
arg_optional (Arg { argData = Just (DataArg { dataArgOptional = b }) }) = b
arg_optional _ = True

--- There's probably a better way to do this
perhaps b s = if b then s else ""

--- Format the described argument as a string
arg_string :: (Ord a) => Arg a -> String
arg_string a@(Arg { argAbbr = abbr,
                    argName = name,
                    argData = arg }) =
               (optionally "[") ++
               (sometimes flag_abbr abbr) ++
               (perhaps ((isJust abbr) && (isJust name)) ",") ++
               (sometimes flag_name name) ++
               (perhaps ((arg_flag a) && (isJust arg)) " ") ++
               (sometimes data_arg arg) ++
               (optionally "]")
    where
      sometimes = maybe ""
      optionally s = perhaps (arg_optional a) s
      flag_name s = "--" ++ s
      flag_abbr c = [ '-', c ]
      data_arg (DataArg {dataArgName = s}) = "<" ++ s ++ ">"

--- Filter out the empty keys for a hash.
filter_keys :: [ (Maybe a, b) ] -> [ (a, b) ]
filter_keys l =
    foldr check_key [] l
    where
      check_key (Nothing, _) rest = rest
      check_key (Just k, v) rest = (k, v) : rest

--- Fail with an error if the argument description is bad
--- for some reason.
argdesc_error :: String -> IO a
argdesc_error msg =
    error ("internal error: argument description: " ++ msg)

--- Make a keymap.
--- We want an error message if the key list contains
--- duplicate keys.
keymap_from_list :: (Ord k, Show k) =>
                    [ (k, a) ] -> IO (Map.Map k a)
keymap_from_list l =
    foldM add_entry Map.empty l
    where
      add_entry m (k, a) =
        case Map.member k m of
          False -> return (Map.insert k a m)
          True -> argdesc_error ("duplicate key " ++ (show k))

--- Make a keymap for looking up a flag argument.
make_keymap :: (Ord a, Ord k, Show k) =>
               ((Arg a) -> Maybe k) ->
               [ Arg a ] ->
               IO (Map.Map k (Arg a))
make_keymap f_field args =
    (keymap_from_list .
     filter_keys .
     map (\arg -> (f_field arg, arg))) args

--- What can be left over after the parse?
data ArgsComplete =
    ArgsComplete |   --- no extraneous arguments
    ArgsTrailing |   --- trailing extraneous arguments OK
    ArgsInterspersed   --- any extraneous arguments OK

--- Given a description of the arguments, parseArgs produces
--- a map from the arguments to their "values" and some other
--- useful byproducts.  Sadly, we're trapped in the IO monad
--- by wanting to report usage errors.
parseArgs :: (Ord a) => ArgsComplete -> [ Arg a ] -> [ String ] -> IO (Args a)
parseArgs complete argd argv = do
  let abbr_hash = make_keymap argAbbr argd
  let name_hash = make_keymap argName argd
  pathname <- getProgName
  let prog_name = baseName pathname
  let usage = make_usage_string prog_name
  hPutStr stderr usage
  error "not done yet"
  return (Args { args = Map.empty,
                 argsProgName = prog_name,
                 argsUsage = usage,
                 argsRest = [] })
  where
    --- Optional arguments must precede fixed arguments.
    --- No argument may be "empty".
    --- Generate a usage message string
    make_usage_string prog_name =
      --- top (summary) line
      (prog_name ++ ": usage: " ++ prog_name) ++
      (perhaps (not (null flag_args))
               " [options]") ++
      (perhaps (not (null posn_args))
               (" " ++ (unwords (map arg_string posn_args)))) ++
      (case complete of
         ArgsComplete -> " [--] ..."
         _ -> "") ++
      "\n" ++
      --- argument lines
      (concatMap (arg_line n) argd)
      where
        flag_args = filter arg_flag argd
        posn_args = filter arg_posn argd
        n = maximum (map (length . arg_string) argd)
        arg_line n a =
          let s = arg_string a in
            "  " ++ s ++ 
            (replicate (n - (length s)) ' ') ++
            "  " ++ (argDesc a) ++ "\n"
