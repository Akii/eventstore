{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DataKinds     #-}
--------------------------------------------------------------------------------
-- |
-- Module : Database.EventStore.Internal.Operation.WriteEventsOperation
-- Copyright : (C) 2014 Yorick Laupa
-- License : (see the file LICENSE)
--
-- Maintainer : Yorick Laupa <yo.eight@gmail.com>
-- Stability : provisional
-- Portability : non-portable
--
--------------------------------------------------------------------------------
module Database.EventStore.Internal.Operation.WriteEventsOperation
    ( writeEventsOperation ) where

--------------------------------------------------------------------------------
import Control.Concurrent
import Data.Int
import Data.Maybe
import Data.Traversable
import GHC.Generics (Generic)
import Prelude

--------------------------------------------------------------------------------
import Data.ProtocolBuffers
import Data.Text

--------------------------------------------------------------------------------
import Database.EventStore.Internal.Manager.Operation
import Database.EventStore.Internal.Types

--------------------------------------------------------------------------------
data WriteEvents
    = WriteEvents
      { _writeStreamId        :: Required 1 (Value Text)
      , _writeExpectedVersion :: Required 2 (Value Int32)
      , _writeEvents          :: Repeated 3 (Message NewEvent)
      , _writeRequireMaster   :: Required 4 (Value Bool)
      }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Encode WriteEvents

--------------------------------------------------------------------------------
newWriteEvents :: Text        -- ^ Stream
               -> Int32       -- ^ Expected version
               -> [NewEvent]  -- ^ Events
               -> Bool        -- ^ Require master
               -> WriteEvents
newWriteEvents stream_id exp_ver evts req_master =
    WriteEvents
    { _writeStreamId        = putField stream_id
    , _writeExpectedVersion = putField exp_ver
    , _writeEvents          = putField evts
    , _writeRequireMaster   = putField req_master
    }

--------------------------------------------------------------------------------
data WriteEventsCompleted
    = WriteEventsCompleted
      { _writeCompletedResult          :: Required 1 (Enumeration OpResult)
      , _writeCompletedMessage         :: Optional 2 (Value Text)
      , _writeCompletedFirstNumber     :: Required 3 (Value Int32)
      , _writeCompletedLastNumber      :: Required 4 (Value Int32)
      , _writeCompletedPreparePosition :: Optional 5 (Value Int64)
      , _writeCompletedCommitPosition  :: Optional 6 (Value Int64)
      }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode WriteEventsCompleted

--------------------------------------------------------------------------------
writeEventsOperation :: Settings
                     -> MVar (OperationExceptional WriteResult)
                     -> Text
                     -> ExpectedVersion
                     -> [Event]
                     -> OperationParams
writeEventsOperation settings mvar evt_stream exp_ver evts =
    OperationParams
    { opSettings    = settings
    , opRequestCmd  = 0x82
    , opResponseCmd = 0x83

    , opRequest = do
        new_evts <- traverse eventToNewEvent evts

        let require_master = s_requireMaster settings
            exp_ver_int32  = expVersionInt32 exp_ver
            request        = newWriteEvents evt_stream
                                                  exp_ver_int32
                                                  new_evts
                                                  require_master
        return request

    , opSuccess = inspect mvar evt_stream exp_ver
    , opFailure = failed mvar
    }

--------------------------------------------------------------------------------
inspect :: MVar (OperationExceptional WriteResult)
        -> Text
        -> ExpectedVersion
        -> WriteEventsCompleted
        -> IO Decision
inspect mvar stream exp_ver wec = go (getField $ _writeCompletedResult wec)
  where
    go OP_SUCCESS                = succeed mvar wec
    go OP_PREPARE_TIMEOUT        = return Retry
    go OP_FORWARD_TIMEOUT        = return Retry
    go OP_COMMIT_TIMEOUT         = return Retry
    go OP_WRONG_EXPECTED_VERSION = failed mvar wrong_version
    go OP_STREAM_DELETED         = failed mvar (StreamDeleted stream)
    go OP_INVALID_TRANSACTION    = failed mvar InvalidTransaction
    go OP_ACCESS_DENIED          = failed mvar (AccessDenied stream)

    wrong_version = WrongExpectedVersion stream exp_ver

--------------------------------------------------------------------------------
succeed :: MVar (OperationExceptional WriteResult)
        -> WriteEventsCompleted
        -> IO Decision
succeed mvar wec = do
    putMVar mvar (Right wr)
    return EndOperation
  where
    last_evt_num = getField $ _writeCompletedLastNumber wec
    com_pos      = getField $ _writeCompletedCommitPosition wec
    pre_pos      = getField $ _writeCompletedPreparePosition wec
    com_pos_int  = fromMaybe (-1) com_pos
    pre_pos_int  = fromMaybe (-1) pre_pos
    pos          = Position com_pos_int pre_pos_int
    wr           = WriteResult last_evt_num pos

--------------------------------------------------------------------------------
failed :: MVar (OperationExceptional WriteResult)
       -> OperationException
       -> IO Decision
failed mvar e = do
    putMVar mvar (Left e)
    return EndOperation

--------------------------------------------------------------------------------
eventToNewEvent :: Event -> IO NewEvent
eventToNewEvent evt =
    newEvent evt_type
             evt_id
             evt_data_type
             evt_metadata_type
             evt_data_bytes
             evt_metadata_bytes
  where
    evt_type           = eventType evt
    evt_id             = eventId evt
    evt_data_bytes     = eventDataBytes $ eventData evt
    evt_data_type      = eventDataType $ eventData evt
    evt_metadata_bytes = eventMetadataBytes $ eventData evt
    evt_metadata_type  = eventMetadataType $ eventData evt
