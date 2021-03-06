{-# LANGUAGE GeneralizedNewtypeDeriving #-}
--------------------------------------------------------------------------------
-- |
-- Module : Database.EventStore.Internal.Command
-- Copyright : (C) 2016 Yorick Laupa
-- License : (see the file LICENSE)
--
-- Maintainer : Yorick Laupa <yo.eight@gmail.com>
-- Stability : provisional
-- Portability : non-portable
--
--------------------------------------------------------------------------------
module Database.EventStore.Internal.Command (Command(..)) where

--------------------------------------------------------------------------------
import ClassyPrelude

--------------------------------------------------------------------------------
import Database.EventStore.Internal.Utils

--------------------------------------------------------------------------------
-- | Internal command representation.
newtype Command = Command { cmdWord8 :: Word8 } deriving (Eq, Ord, Num)

--------------------------------------------------------------------------------
instance Show Command where
    show (Command w) = prettyWord8 w
