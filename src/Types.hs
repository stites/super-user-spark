{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE UndecidableInstances  #-}
module Types
    (
      module Types
    , module CoreTypes
    , module Monad
    , module Config.Types

    , module Control.Monad.Except
    , module Control.Monad.IO.Class
    , module Control.Monad.Reader
    , module Control.Monad.State
    , module Control.Monad.Writer
    , module Control.Monad.Trans
    , module Control.Monad.Identity
    , module Text.Parsec

    , module Debug.Trace
    ) where

import           Control.Monad.Except   (ExceptT, mapExceptT, runExceptT,
                                         throwError, withExceptT)
import           Control.Monad.Identity (Identity, runIdentity)
import           Control.Monad.IO.Class (MonadIO (..), liftIO)
import           Control.Monad.Reader   (MonadReader (..), ReaderT, ask, asks,
                                         mapReaderT, runReaderT)
import           Control.Monad.State    (MonadState (..), StateT, evalStateT,
                                         execStateT, get, gets, modify, put,
                                         runStateT)
import           Control.Monad.Trans    (lift)
import           Control.Monad.Writer   (MonadWriter (..), WriterT, execWriterT,
                                         runWriterT, tell)
import           Debug.Trace

import           Text.Parsec            (ParseError)

import           Config.Types
import           CoreTypes
import           Monad

---[ Options ]---
data GlobalOptions = GlobalOptions
    { opt_lineUp              :: Bool
    , opt_indent              :: Int
    , opt_trailingNewline     :: Bool
    , opt_alwaysQuote         :: Bool
    , opt_compress            :: Bool
    , opt_output              :: Maybe FilePath
    , opt_format              :: CompileFormat
    , opt_kind                :: Maybe DeploymentKind
    , opt_overrride           :: Maybe DeploymentKind
    , opt_thoroughness        :: CheckThoroughness
    , opt_replace_links       :: Bool
    , opt_replace_files       :: Bool
    , opt_replace_directories :: Bool
    , opt_replace             :: Bool
    , opt_debug               :: Bool
    } deriving (Show, Eq)

---[ Pretty Types ]---

type SparkFormatter = StateT FormatterState (WriterT String Sparker)
data FormatterState = FormatterState
    { state_current_indent        :: Int
    , state_longest_src           :: Int
    , state_newline_before_deploy :: Bool
    } deriving (Show, Eq)

runSparkFormatter :: FormatterState -> SparkFormatter a -> Sparker ((a, FormatterState), String)
runSparkFormatter state func = runWriterT (runStateT func state)

