{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# OPTIONS_GHC -fcontext-stack=26     #-}
--------------------------------------------------------------------------------
-- |
-- Module : Database.EventStore.Internal.Manager.Subscription.Message
-- Copyright : (C) 2015 Yorick Laupa
-- License : (see the file LICENSE)
--
-- Maintainer : Yorick Laupa <yo.eight@gmail.com>
-- Stability : provisional
-- Portability : non-portable
--
--------------------------------------------------------------------------------
module Database.EventStore.Internal.Manager.Subscription.Message where

--------------------------------------------------------------------------------
import Data.ByteString (ByteString)
import Data.Int
import GHC.Generics (Generic)

--------------------------------------------------------------------------------
import Data.ProtocolBuffers
import Data.Text (Text)

--------------------------------------------------------------------------------
import Database.EventStore.Internal.TimeSpan
import Database.EventStore.Internal.Types

--------------------------------------------------------------------------------
data SubscribeToStream
    = SubscribeToStream
      { subscribeStreamId       :: Required 1 (Value Text)
      , subscribeResolveLinkTos :: Required 2 (Value Bool)
      }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Encode SubscribeToStream

--------------------------------------------------------------------------------
subscribeToStream :: Text -> Bool -> SubscribeToStream
subscribeToStream stream_id res_link_tos =
    SubscribeToStream
    { subscribeStreamId       = putField stream_id
    , subscribeResolveLinkTos = putField res_link_tos
    }

--------------------------------------------------------------------------------
data SubscriptionConfirmation
    = SubscriptionConfirmation
      { subscribeLastCommitPos   :: Required 1 (Value Int64)
      , subscribeLastEventNumber :: Optional 2 (Value Int32)
      }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode SubscriptionConfirmation

--------------------------------------------------------------------------------
data StreamEventAppeared
    = StreamEventAppeared
      { streamResolvedEvent :: Required 1 (Message ResolvedEventBuf) }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode StreamEventAppeared

--------------------------------------------------------------------------------
-- | Represents the reason subscription drop happened.
data DropReason
    = D_Unsubscribed
    | D_AccessDenied
    | D_NotFound
    | D_PersistentSubscriptionDeleted
    deriving (Enum, Eq, Show)

--------------------------------------------------------------------------------
data SubscriptionDropped
    = SubscriptionDropped
      { dropReason :: Optional 1 (Enumeration DropReason) }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode SubscriptionDropped

--------------------------------------------------------------------------------
data UnsubscribeFromStream = UnsubscribeFromStream deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Encode UnsubscribeFromStream

--------------------------------------------------------------------------------
data CreatePersistentSubscription =
    CreatePersistentSubscription
    { cpsGroupName         :: Required 1  (Value Text)
    , cpsStreamId          :: Required 2  (Value Text)
    , cpsResolveLinkTos    :: Required 3  (Value Bool)
    , cpsStartFrom         :: Required 4  (Value Int32)
    , cpsMsgTimeout        :: Required 5  (Value Int32)
    , cpsRecordStats       :: Required 6  (Value Bool)
    , cpsLiveBufSize       :: Required 7  (Value Int32)
    , cpsReadBatchSize     :: Required 8  (Value Int32)
    , cpsBufSize           :: Required 9  (Value Int32)
    , cpsMaxRetryCount     :: Required 10 (Value Int32)
    , cpsPreferRoundRobin  :: Required 11 (Value Bool)
    , cpsChkPtAfterTime    :: Required 12 (Value Int32)
    , cpsChkPtMaxCount     :: Required 13 (Value Int32)
    , cpsChkPtMinCount     :: Required 14 (Value Int32)
    , cpsSubMaxCount       :: Required 15 (Value Int32)
    , cpsNamedConsStrategy :: Optional 16 (Value Text)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
_createPersistentSubscription :: Text
                              -> Text
                              -> PersistentSubscriptionSettings
                              -> CreatePersistentSubscription
_createPersistentSubscription group stream sett =
    CreatePersistentSubscription
    { cpsGroupName         = putField group
    , cpsStreamId          = putField stream
    , cpsResolveLinkTos    = putField $ psSettingsResolveLinkTos sett
    , cpsStartFrom         = putField $ psSettingsStartFrom sett
    , cpsMsgTimeout        = putField $ ms $ psSettingsMsgTimeout sett
    , cpsRecordStats       = putField $ psSettingsExtraStats sett
    , cpsLiveBufSize       = putField $ psSettingsLiveBufSize sett
    , cpsReadBatchSize     = putField $ psSettingsReadBatchSize sett
    , cpsBufSize           = putField $ psSettingsHistoryBufSize sett
    , cpsMaxRetryCount     = putField $ psSettingsMaxRetryCount sett
    , cpsPreferRoundRobin  = putField False
    , cpsChkPtAfterTime    = putField $ ms $ psSettingsCheckPointAfter sett
    , cpsChkPtMaxCount     = putField $ psSettingsMaxCheckPointCount sett
    , cpsChkPtMinCount     = putField $ psSettingsMinCheckPointCount sett
    , cpsSubMaxCount       = putField $ psSettingsMaxSubsCount sett
    , cpsNamedConsStrategy = putField $ Just strText
    }
  where
    strText = strategyText $ psSettingsNamedConsumerStrategy sett
    ms      = fromIntegral . timeSpanTotalMillis

--------------------------------------------------------------------------------
instance Encode CreatePersistentSubscription

--------------------------------------------------------------------------------
data CreatePersistentSubscriptionResult
    = CPS_Success
    | CPS_AlreadyExists
    | CPS_Fail
    | CPS_AccessDenied
    deriving (Enum, Eq, Show)

--------------------------------------------------------------------------------
data CreatePersistentSubscriptionCompleted =
    CreatePersistentSubscriptionCompleted
    { cpscResult :: Required 1 (Enumeration CreatePersistentSubscriptionResult)
    , cpscReason :: Optional 2 (Value Text)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode CreatePersistentSubscriptionCompleted

--------------------------------------------------------------------------------
data DeletePersistentSubscription =
    DeletePersistentSubscription
    { dpsGroupName :: Required 1 (Value Text)
    , dpsStreamId  :: Required 2 (Value Text)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Encode DeletePersistentSubscription

--------------------------------------------------------------------------------
_deletePersistentSubscription :: Text -> Text -> DeletePersistentSubscription
_deletePersistentSubscription group_name stream_id =
    DeletePersistentSubscription
    { dpsGroupName = putField group_name
    , dpsStreamId  = putField stream_id
    }

--------------------------------------------------------------------------------
data DeletePersistentSubscriptionResult
    = DPS_Success
    | DPS_DoesNotExist
    | DPS_Fail
    | DPS_AccessDenied
    deriving (Enum, Eq, Show)

--------------------------------------------------------------------------------
data DeletePersistentSubscriptionCompleted =
    DeletePersistentSubscriptionCompleted
    { dpscResult :: Required 1 (Enumeration DeletePersistentSubscriptionResult)
    , dpscReason :: Optional 2 (Value Text)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode DeletePersistentSubscriptionCompleted

--------------------------------------------------------------------------------
data UpdatePersistentSubscription =
    UpdatePersistentSubscription
    { upsGroupName         :: Required 1  (Value Text)
    , upsStreamId          :: Required 2  (Value Text)
    , upsResolveLinkTos    :: Required 3  (Value Bool)
    , upsStartFrom         :: Required 4  (Value Int32)
    , upsMsgTimeout        :: Required 5  (Value Int32)
    , upsRecordStats       :: Required 6  (Value Bool)
    , upsLiveBufSize       :: Required 7  (Value Int32)
    , upsReadBatchSize     :: Required 8  (Value Int32)
    , upsBufSize           :: Required 9  (Value Int32)
    , upsMaxRetryCount     :: Required 10 (Value Int32)
    , upsPreferRoundRobin  :: Required 11 (Value Bool)
    , upsChkPtAfterTime    :: Required 12 (Value Int32)
    , upsChkPtMaxCount     :: Required 13 (Value Int32)
    , upsChkPtMinCount     :: Required 14 (Value Int32)
    , upsSubMaxCount       :: Required 15 (Value Int32)
    , upsNamedConsStrategy :: Optional 16 (Value Text)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
_updatePersistentSubscription :: Text
                              -> Text
                              -> PersistentSubscriptionSettings
                              -> UpdatePersistentSubscription
_updatePersistentSubscription group stream sett =
    UpdatePersistentSubscription
    { upsGroupName         = putField group
    , upsStreamId          = putField stream
    , upsResolveLinkTos    = putField $ psSettingsResolveLinkTos sett
    , upsStartFrom         = putField $ psSettingsStartFrom sett
    , upsMsgTimeout        = putField $ ms $ psSettingsMsgTimeout sett
    , upsRecordStats       = putField $ psSettingsExtraStats sett
    , upsLiveBufSize       = putField $ psSettingsLiveBufSize sett
    , upsReadBatchSize     = putField $ psSettingsReadBatchSize sett
    , upsBufSize           = putField $ psSettingsHistoryBufSize sett
    , upsMaxRetryCount     = putField $ psSettingsMaxRetryCount sett
    , upsPreferRoundRobin  = putField False
    , upsChkPtAfterTime    = putField $ ms $ psSettingsCheckPointAfter sett
    , upsChkPtMaxCount     = putField $ psSettingsMaxCheckPointCount sett
    , upsChkPtMinCount     = putField $ psSettingsMinCheckPointCount sett
    , upsSubMaxCount       = putField $ psSettingsMaxSubsCount sett
    , upsNamedConsStrategy = putField $ Just strText
    }
  where
    strText = strategyText $ psSettingsNamedConsumerStrategy sett
    ms      = fromIntegral . timeSpanTotalMillis

--------------------------------------------------------------------------------
instance Encode UpdatePersistentSubscription

--------------------------------------------------------------------------------
data UpdatePersistentSubscriptionResult
    = UPS_Success
    | UPS_DoesNotExist
    | UPS_Fail
    | UPS_AccessDenied
    deriving (Enum, Eq, Show)

--------------------------------------------------------------------------------
data UpdatePersistentSubscriptionCompleted =
    UpdatePersistentSubscriptionCompleted
    { upscResult :: Required 1 (Enumeration UpdatePersistentSubscriptionResult)
    , upscReason :: Optional 2 (Value Text)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode UpdatePersistentSubscriptionCompleted

--------------------------------------------------------------------------------
data ConnectToPersistentSubscription =
    ConnectToPersistentSubscription
    { ctsId                  :: Required 1 (Value Text)
    , ctsStreamId            :: Required 2 (Value Text)
    , ctsAllowedInFlightMsgs :: Required 3 (Value Int32)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Encode ConnectToPersistentSubscription

--------------------------------------------------------------------------------
_connectToPersistentSubscription :: Text
                                 -> Text
                                 -> Int32
                                 -> ConnectToPersistentSubscription
_connectToPersistentSubscription sub_id stream_id all_fly_msgs =
    ConnectToPersistentSubscription
    { ctsId                  = putField sub_id
    , ctsStreamId            = putField stream_id
    , ctsAllowedInFlightMsgs = putField all_fly_msgs
    }

--------------------------------------------------------------------------------
data PersistentSubscriptionAckEvents =
    PersistentSubscriptionAckEvents
    { psaeId              :: Required 1 (Value Text)
    , psaeProcessedEvtIds :: Required 2 (Value ByteString)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Encode PersistentSubscriptionAckEvents

--------------------------------------------------------------------------------
persistentSubscriptionAckEvents :: Text
                                -> ByteString
                                -> PersistentSubscriptionAckEvents
persistentSubscriptionAckEvents sub_id evt_ids =
    PersistentSubscriptionAckEvents
    { psaeId              = putField sub_id
    , psaeProcessedEvtIds = putField evt_ids
    }

--------------------------------------------------------------------------------
data NakAction
    = NA_Unknown
    | NA_Park
    | NA_Retry
    | NA_Skip
    | NA_Stop
    deriving (Enum, Eq, Show)

--------------------------------------------------------------------------------
data PersistentSubscriptionNakEvents =
    PersistentSubscriptionNakEvents
    { psneId              :: Required 1 (Value Text)
    , psneProcessedEvtIds :: Required 2 (Value ByteString)
    , psneMsg             :: Optional 3 (Value Text)
    , psneAction          :: Required 4 (Enumeration NakAction)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Encode PersistentSubscriptionNakEvents

--------------------------------------------------------------------------------
persistentSubscriptionNakEvents :: Text
                                -> ByteString
                                -> Maybe Text
                                -> NakAction
                                -> PersistentSubscriptionNakEvents
persistentSubscriptionNakEvents sub_id evt_ids msg action =
    PersistentSubscriptionNakEvents
    { psneId              = putField sub_id
    , psneProcessedEvtIds = putField evt_ids
    , psneMsg             = putField msg
    , psneAction          = putField action
    }

--------------------------------------------------------------------------------
data PersistentSubscriptionConfirmation =
    PersistentSubscriptionConfirmation
    { pscLastCommitPos :: Required 1 (Value Int64)
    , pscId            :: Required 2 (Value Text)
    , pscLastEvtNumber :: Optional 3 (Value Int32)
    } deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode PersistentSubscriptionConfirmation

--------------------------------------------------------------------------------
data PersistentSubscriptionStreamEventAppeared =
    PersistentSubscriptionStreamEventAppeared
    { psseaEvt :: Required 1 (Message ResolvedIndexedEvent) }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode PersistentSubscriptionStreamEventAppeared