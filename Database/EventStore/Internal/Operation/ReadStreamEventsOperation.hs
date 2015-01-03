{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DataKinds     #-}
--------------------------------------------------------------------------------
-- |
-- Module : Database.EventStore.Internal.Operation.ReadStreamEventsOperation
-- Copyright : (C) 2014 Yorick Laupa
-- License : (see the file LICENSE)
--
-- Maintainer : Yorick Laupa <yo.eight@gmail.com>
-- Stability : provisional
-- Portability : non-portable
--
--------------------------------------------------------------------------------
module Database.EventStore.Internal.Operation.ReadStreamEventsOperation
    ( StreamEventsSlice(..)
    , ReadStreamResult(..)
    , readStreamEventsOperation
    ) where

--------------------------------------------------------------------------------
import Control.Concurrent
import Data.Int
import GHC.Generics (Generic)

--------------------------------------------------------------------------------
import Data.ProtocolBuffers
import Data.Text

--------------------------------------------------------------------------------
import Database.EventStore.Internal.Manager.Operation
import Database.EventStore.Internal.Types

--------------------------------------------------------------------------------
data ReadStreamEvents
    = ReadStreamEvents
      { _readStreamId             :: Required 1 (Value Text)
      , _readStreamEventNumber    :: Required 2 (Value Int32)
      , _readStreamMaxCount       :: Required 3 (Value Int32)
      , _readStreamResolveLinkTos :: Required 4 (Value Bool)
      , _readStreamRequireMaster  :: Required 5 (Value Bool)
      }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
newReadStreamEvents :: Text
                    -> Int32
                    -> Int32
                    -> Bool
                    -> Bool
                    -> ReadStreamEvents
newReadStreamEvents stream_id evt_num max_c res_link_tos req_master =
    ReadStreamEvents
    { _readStreamId             = putField stream_id
    , _readStreamEventNumber    = putField evt_num
    , _readStreamMaxCount       = putField max_c
    , _readStreamResolveLinkTos = putField res_link_tos
    , _readStreamRequireMaster  = putField req_master
    }

--------------------------------------------------------------------------------
instance Encode ReadStreamEvents

--------------------------------------------------------------------------------
-- | Enumeration detailing the possible outcomes of reading a slice of a stream
data ReadStreamResult
    = RS_SUCCESS
    | RS_NO_STREAM
    | RS_STREAM_DELETED
    | RS_NOT_MODIFIED
    | RS_ERROR
    | RS_ACCESS_DENIED
    deriving (Eq, Enum, Show)

--------------------------------------------------------------------------------
data ReadStreamEventsCompleted
    = ReadStreamEventsCompleted
      { _readSECEvents             :: Repeated 1 (Message ResolvedIndexedEvent)
      , _readSECResult             :: Required 2 (Enumeration ReadStreamResult)
      , _readSECNextNumber         :: Required 3 (Value Int32)
      , _readSECLastNumber         :: Required 4 (Value Int32)
      , _readSECEndOfStream        :: Required 5 (Value Bool)
      , _readSECLastCommitPosition :: Required 6 (Value Int64)
      , _readSECError              :: Optional 7 (Value Text)
      }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode ReadStreamEventsCompleted

--------------------------------------------------------------------------------
-- | Represents the result of a single read operation to the EventStore.
data StreamEventsSlice
    = StreamEventsSlice
      { streamEventsSliceResult :: !ReadStreamResult
        -- ^ Representing the status of the read attempt.
      , streamEventsSliceStreamId :: !Text
        -- ^ The name of the stream read.
      , streamEventsSliceStart :: !Int32
        -- ^ The starting point (represented as a sequence number) of the read
        --   operation.
      , streamEventsSliceNext :: !Int32
        -- ^ The next event number that can be read.
      , streamEventsSliceLast :: !Int32
        -- ^ The last event number in the stream.
      , streamEventsSliceIsEOS :: !Bool
        -- ^ Representing whether or not this is the end of the stream.
      , streamEventsSliceEvents :: ![ResolvedEvent]
        -- ^ The events read represented as 'ResolvedEvent'
      , streamEventsSliceDirection :: !ReadDirection
        -- ^ The direction of the read request.
      }
    deriving Show

--------------------------------------------------------------------------------
newStreamEventsSlice :: Text
                     -> Int32
                     -> ReadDirection
                     -> ReadStreamEventsCompleted
                     -> StreamEventsSlice
newStreamEventsSlice stream_id start dir reco = ses
  where
    evts = getField $ _readSECEvents reco

    ses = StreamEventsSlice
          { streamEventsSliceResult    = getField $ _readSECResult reco
          , streamEventsSliceStreamId  = stream_id
          , streamEventsSliceStart     = start
          , streamEventsSliceNext      = getField $ _readSECNextNumber reco
          , streamEventsSliceLast      = getField $ _readSECLastNumber reco
          , streamEventsSliceIsEOS     = getField $ _readSECEndOfStream reco
          , streamEventsSliceEvents    = fmap newResolvedEvent evts
          , streamEventsSliceDirection = dir
          }

--------------------------------------------------------------------------------
readStreamEventsOperation :: Settings
                          -> ReadDirection
                          -> MVar (OperationExceptional StreamEventsSlice)
                          -> Text
                          -> Int32
                          -> Int32
                          -> Bool
                          -> OperationParams
readStreamEventsOperation settings dir mvar stream_id start cnt res_link_tos =
    OperationParams
    { opSettings    = settings
    , opRequestCmd  = req
    , opResponseCmd = resp

    , opRequest =
        let req_master = s_requireMaster settings
            request    = newReadStreamEvents stream_id
                                             start
                                             cnt
                                             res_link_tos
                                             req_master in
         return request

    , opSuccess = inspect mvar dir stream_id start
    , opFailure = failed mvar
    }
  where
    req = case dir of
              Forward  -> 0xB2
              Backward -> 0xB4

    resp = case dir of
               Forward  -> 0xB3
               Backward -> 0xB5

--------------------------------------------------------------------------------
inspect :: MVar (OperationExceptional StreamEventsSlice)
        -> ReadDirection
        -> Text
        -> Int32
        -> ReadStreamEventsCompleted
        -> IO Decision
inspect mvar dir stream_id start rsec = go (getField $ _readSECResult rsec)
  where
    may_err = getField $ _readSECError rsec

    go RS_ERROR         = failed mvar (ServerError may_err)
    go RS_ACCESS_DENIED = failed mvar (AccessDenied stream_id)
    go _                = succeed mvar dir stream_id start rsec

--------------------------------------------------------------------------------
succeed :: MVar (OperationExceptional StreamEventsSlice)
        -> ReadDirection
        -> Text
        -> Int32
        -> ReadStreamEventsCompleted
        -> IO Decision
succeed mvar dir stream_id start rsec = do
    putMVar mvar (Right ses)
    return EndOperation
  where
    ses = newStreamEventsSlice stream_id start dir rsec

--------------------------------------------------------------------------------
failed :: MVar (OperationExceptional StreamEventsSlice)
       -> OperationException
       -> IO Decision
failed mvar e = do
    putMVar mvar (Left e)
    return EndOperation
