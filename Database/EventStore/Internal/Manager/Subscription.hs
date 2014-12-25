{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE MultiWayIf            #-}
{-# LANGUAGE RecordWildCards       #-}
{-# OPTIONS_GHC -fcontext-stack=26 #-}
--------------------------------------------------------------------------------
-- |
-- Module : Database.EventStore.Internal.Manager.Subscription
-- Copyright : (C) 2014 Yorick Laupa
-- License : (see the file LICENSE)
--
-- Maintainer : Yorick Laupa <yo.eight@gmail.com>
-- Stability : provisional
-- Portability : non-portable
--
--------------------------------------------------------------------------------
module Database.EventStore.Internal.Manager.Subscription
    ( Subscription(..)
    , subscriptionNetwork
    ) where

--------------------------------------------------------------------------------
import           Control.Concurrent.STM
import           Control.Monad.Fix
import           Data.ByteString (ByteString)
import           Data.Int
import qualified Data.Map.Strict as M
import           Data.Maybe
import           Data.Monoid ((<>))
import           Data.Traversable (for)
import           Data.Word
import           GHC.Generics (Generic)

--------------------------------------------------------------------------------
import Data.ProtocolBuffers
import Data.Serialize
import Data.Text
import Data.UUID
import FRP.Sodium
import FRP.Sodium.IO
import System.Random

--------------------------------------------------------------------------------
import Database.EventStore.Internal.Types hiding (Event, newEvent)
import Database.EventStore.Internal.Util.Sodium

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
data DropReason
    = Unsubscribed
    | AccessDenied
    | NotFound
    | PersistentSubscriptionDeleted
    deriving (Enum, Eq, Show)

--------------------------------------------------------------------------------
data SubscriptionDropped
    = SubscriptionDropped
      { dropReason :: Optional 1 (Enumeration DropReason) }
    deriving (Generic, Show)

--------------------------------------------------------------------------------
instance Decode SubscriptionDropped

--------------------------------------------------------------------------------
data Pending
    = Pending
      { penConfirmed :: Int64 -> Maybe Int32 -> IO Subscription
      , penCallback  :: Subscription -> IO ()
      }

--------------------------------------------------------------------------------
data SubscriptionException
    = StreamAccessDenied
    | StreamNotFound
    | SubscriptionDeleted
    deriving Show

--------------------------------------------------------------------------------
data Subscription
    = Subscription
      { subId              :: !UUID
      , subStream          :: !Text
      , subResolveLinkTos  :: !Bool
      , subEventChan       :: !(TChan (Either DropReason ResolvedEventBuf))
      , subLastCommitPos   :: !Int64
      , subLastEventNumber :: !(Maybe Int32)
      , subUnsubscribe     :: IO ()
      }

--------------------------------------------------------------------------------
data Manager
    = Manager
      { _pendings      :: !(M.Map UUID Pending)
      , _subscriptions :: !(M.Map UUID Subscription)
      }

--------------------------------------------------------------------------------
initManager :: Manager
initManager = Manager M.empty M.empty

--------------------------------------------------------------------------------
-- Handled Packages
--------------------------------------------------------------------------------
subscriptionConfirmed :: Word8
subscriptionConfirmed = 0xC1

--------------------------------------------------------------------------------
streamEventAppeared :: Word8
streamEventAppeared = 0xC2

--------------------------------------------------------------------------------
subscriptionDropped :: Word8
subscriptionDropped = 0xC4

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
maybeDecodeMessage :: Decode a => ByteString -> Maybe a
maybeDecodeMessage bytes =
    case runGet decodeMessage bytes of
        Right a -> Just a
        _       -> Nothing

--------------------------------------------------------------------------------
onConfirmation :: Package -> Maybe Confirmation
onConfirmation Package{..}
    | packageCmd == subscriptionConfirmed =
          fmap (Confirmation packageCorrelation) $
          maybeDecodeMessage packageData
    | otherwise = Nothing

--------------------------------------------------------------------------------
data Appeared
    = Appeared
      { _appSub :: !Subscription
      , _appEvt :: !ResolvedEventBuf
      }

--------------------------------------------------------------------------------
onEventAppeared :: Package -> Manager -> Maybe Appeared
onEventAppeared Package{..} Manager{..}
    | packageCmd == streamEventAppeared = do
          sub <- M.lookup packageCorrelation _subscriptions
          sea <- maybeDecodeMessage packageData
          let res_evt = getField $ streamResolvedEvent sea
              app     = Appeared sub res_evt

          return app
    | otherwise = Nothing

--------------------------------------------------------------------------------
confirmSub :: Confirmation -> Manager -> IO (Maybe Subscription)
confirmSub (Confirmation uuid sc) Manager{..} =
    for (M.lookup uuid _pendings) $ \p -> do
        let last_com_pos = getField $ subscribeLastCommitPos sc
            last_evt_num = getField $ subscribeLastEventNumber sc

        sub <- penConfirmed p last_com_pos last_evt_num
        penCallback p sub
        return sub

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
data Subscribe
    = Subscribe
      { _subId             :: !UUID
      , _subCallback       :: Subscription -> IO ()
      , _subStream         :: !Text
      , _subResolveLinkTos :: !Bool
      }

--------------------------------------------------------------------------------
data Confirmation = Confirmation !UUID !SubscriptionConfirmation

--------------------------------------------------------------------------------
type NewSubscription = (Subscription -> IO ()) -> Text -> Bool -> IO ()

--------------------------------------------------------------------------------
subscriptionNetwork :: (Package -> Reactive ())
                    -> Event Package
                    -> Reactive NewSubscription
subscriptionNetwork push_pkg e_pkg = do
    (on_sub, push_sub) <- newEvent
    (on_rem, push_rem) <- newEvent

    mgr_b <- mfix $ \mgr_b -> do
        let on_con     = filterJust $ fmap onConfirmation e_pkg
            on_con_sub = filterJust $ executeSyncIO $ snapshot confirmSub
                                                               on_con
                                                               mgr_b
            mgr_e = fmap (subscribe push_rem) on_sub <>
                    fmap remove on_rem               <>
                    fmap confirmed on_con_sub

        accum initManager mgr_e

    let on_app      = filterJust $ snapshot onEventAppeared e_pkg mgr_b
        on_drop     = filterJust $ execute $ snapshot (dropError push_rem)
                                                      e_pkg
                                                      mgr_b
        push_pkg_io = pushAsync push_pkg

        push_sub_io cb stream res_lnk_tos = randomIO >>= \uuid -> sync $
            push_sub Subscribe
                     { _subId             = uuid
                     , _subCallback       = cb
                     , _subStream         = stream
                     , _subResolveLinkTos = res_lnk_tos
                     }

    _ <- listen on_sub (push_pkg_io . createSubscribePackage)

    _ <- listen on_app $ \(Appeared sub evt) ->
        atomically $ writeTChan (subEventChan sub) (Right evt)

    _ <- listen on_drop $ \(Dropped reason sub _) ->
        atomically $ writeTChan (subEventChan sub) (Left reason)

    return push_sub_io

--------------------------------------------------------------------------------
createSubscribePackage :: Subscribe -> Package
createSubscribePackage Subscribe{..} =
    Package
    { packageCmd         = 0xC0
    , packageFlag        = None
    , packageCorrelation = _subId
    , packageData        = runPut $ encodeMessage msg
    }
  where
    msg = subscribeToStream _subStream _subResolveLinkTos

--------------------------------------------------------------------------------
data Dropped
    = Dropped
      { droppedReason :: !DropReason
      , droppedSub    :: !Subscription
      , droppedId     :: !UUID
      }

--------------------------------------------------------------------------------
dropError :: (UUID -> Reactive ())
          -> Package
          -> Manager
          -> Reactive (Maybe Dropped)
dropError push_rem Package{..} Manager{..} =
    for go $ \d -> do
        push_rem $ droppedId d
        return d
  where
    go | packageCmd == subscriptionDropped = do
             sub <- M.lookup packageCorrelation _subscriptions
             msg <- maybeDecodeMessage packageData
             let reason  = fromMaybe Unsubscribed $ getField $ dropReason msg
                 dropped = Dropped
                           { droppedReason = reason
                           , droppedSub    = sub
                           , droppedId     = packageCorrelation
                           }

             return dropped
       | otherwise = Nothing

--------------------------------------------------------------------------------
-- Model
--------------------------------------------------------------------------------
subscribe :: (UUID -> Reactive ()) -> Subscribe -> Manager -> Manager
subscribe unsub Subscribe{..} s@Manager{..} =
    s { _pendings = M.insert _subId pending _pendings }
  where
    pending =
        Pending
        { penConfirmed = new_sub
        , penCallback  = _subCallback
        }

    new_sub com_pos last_evt = do
        chan <- newTChanIO
        let sub = Subscription
                  { subId              = _subId
                  , subStream          = _subStream
                  , subResolveLinkTos  = _subResolveLinkTos
                  , subEventChan       = chan
                  , subLastCommitPos   = com_pos
                  , subLastEventNumber = last_evt
                  , subUnsubscribe     = sync $ unsub _subId
                  }

        return sub

--------------------------------------------------------------------------------
confirmed :: Subscription -> Manager -> Manager
confirmed sub@Subscription{..} s@Manager{..} =
    s { _pendings      = M.delete subId _pendings
      , _subscriptions = M.insert subId sub _subscriptions
      }

--------------------------------------------------------------------------------
remove :: UUID -> Manager -> Manager
remove uuid s@Manager{..} = s { _subscriptions = M.delete uuid _subscriptions }
