--- Full-featured argument parser
--- Bart Massey 2007/01/06
---
--- Copyright (C) 2007 Bart Massey
--- ALL RIGHTS RESERVED

module ParseArgs (ArgVal(..), ArgAtype(..),
                  Arg(..), ArgDesc(..), Args(..),
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

--- The kinds of "value" an argument can have.
data ArgVal =
    ArgValFlag |
    ArgValString String |
    ArgValInt Int

--- The corresponding argument type requirements
data ArgAtype =
    ArgAtypeFlag |
    ArgAtypeString |
    ArgAtypeInt

--- The description of an argument, suitable for
--- messages and for parsing.
--- It is expected that each argument be identified
--- by an enumeration value, so that its value can easily
--- be referenced later.
data (Ord a) => Arg a =
    Arg { argIndex :: a,
          argAtype :: ArgAtype,
          argName :: String,
          argAbbr :: Maybe Char,
          argExprName :: Maybe String,
          argDesc :: String }

--- The full description of the parsing problem for
--- parseArgs to swallow.
data ArgDesc a =
    ArgDesc { argDescArgs :: [ Arg a ],
              argDescPosnArgs :: [ Arg a ],
              argDescOptArgs :: [ Arg a ],
              argDescComplete :: Bool }

--- The data structure parseArgs produces.
data (Ord a) => Args a =
    Args { args :: Map.Map a ArgVal,
           argsProgName :: String,
           argsUsage :: Handle -> String -> IO (),
           argsRest :: [ String ] }

--- Return the filename part of 'path'.
--- Unnecessarily efficient implementation does a single
--- tail-call traversal with no construction.
baseName :: String -> String
baseName s =
    let s' = dropWhile (/= '/') s in
    if null s' then s else baseName (tail s')


--- Given an arg desc, produce a description string.
--- Note that this works regardless of the argAtype,
--- which it ignores.
arg_string :: (Ord a) => Arg a -> String
arg_string (Arg { argAbbr = abbr,
                  argName = name,
                  argExprName = exprName }) =
    case exprName of
      Nothing -> flag_part
      Just s -> flag_part ++ " <" ++ s ++ ">"
    where
      flag_part :: String
      flag_part =
          (case abbr of
             Nothing -> ""
             Just c -> "-" ++ [c] ++ ",") ++
          "--" ++
          name

--- Filter out the empty keys for a hash.
filter_keys :: [ (Maybe a, b) ] -> [ (a, b) ]
filter_keys l =
    foldr check_key [] l
    where
      check_key :: (Maybe a, b) -> [ (a, b) ] -> [ (a, b) ]
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
      add_entry :: (Ord k, Show k) =>
                   (Map.Map k a) -> (k, a) -> IO (Map.Map k a)
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

--- Given a description of the arguments, parseArgs produces
--- a map from the arguments to their "values" and some other
--- useful byproducts.  Sadly, we're trapped in the IO monad
--- by wanting to report usage errors.
parseArgs :: (Ord a) => ArgDesc a -> [ String ] -> IO (Args a)
parseArgs argd argv = do
  let ads = argDescArgs argd
  let abbr_hash = make_keymap argAbbr ads
  let name_hash = make_keymap (Just . argName) ads
  pathname <- getProgName
  let prog_name = baseName pathname
  let h_usage = mk_h_usage prog_name
  let usage = h_usage stderr
  usage "not done yet"
  return (Args { args = Map.empty,
                 argsProgName = prog_name,
                 argsUsage = h_usage,
                 argsRest = [] })
  where
    --- Print a usage message on the given handle.
    mk_h_usage :: String -> Handle -> String -> IO ()
    mk_h_usage prog_name h msg = do
      --- top (summary) line
      hPutStr h (prog_name ++ ": usage: " ++ prog_name)
      let args = argDescArgs argd
      unless (null args)
             (hPutStr h " [options]")
      let posn_args = argDescPosnArgs argd
      unless (null posn_args)
             (mapM_ ((hPutStr h) . (format_posn "<" ">")) posn_args)
      let opt_args = argDescOptArgs argd
      unless (null opt_args)
             (mapM_ ((hPutStr h) . (format_posn "[" "]")) opt_args)
      let complete = argDescComplete argd
      unless complete
             (hPutStr h " [--] ...")
      hPutStrLn h ""
      --- argument lines
      let lhs = (map arg_string args) ++
                (map argName posn_args) ++
                (map argName opt_args)
      let n = maximum (map length lhs)
      mapM_ (put_line n arg_string) args
      mapM_ (put_line n argName) posn_args
      mapM_ (put_line n argName) opt_args
      --- bail
      hPutStrLn h ""
      error ("usage error: " ++ msg)
      where
        format_posn :: (Ord a) => String -> String -> Arg a -> String
        format_posn l r a =  " " ++ l ++ (argName a) ++ r
        put_line :: (Ord a) => Int -> (Arg a -> String) -> Arg a -> IO ()
        put_line n f a =
            hPutStrLn h ("  " ++ (pad_width n (f a)) ++ "  " ++ argDesc a)
        pad_width :: Int -> String -> String
        pad_width n s =
            s ++ (replicate (n - (length s)) ' ')
