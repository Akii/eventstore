{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
--------------------------------------------------------------------------------
-- |
-- Module : Tests
-- Copyright : (C) 2015 Yorick Laupa
-- License : (see the file LICENSE)
--
-- Maintainer : Yorick Laupa <yo.eight@gmail.com>
-- Stability : provisional
-- Portability : non-portable
--
-- Gathers all EventStore operations tests.
--------------------------------------------------------------------------------
module Tests where

--------------------------------------------------------------------------------
import Control.Exception
import Data.Maybe (catMaybes)

--------------------------------------------------------------------------------
import Data.Aeson
import Test.Tasty
import Test.Tasty.HUnit

--------------------------------------------------------------------------------
import Database.EventStore

--------------------------------------------------------------------------------
tests :: Connection -> TestTree
tests conn = testGroup "EventStore actions tests"
    [ testCase "Write event" $ writeEventTest conn
    , testCase "Read event" $ readEventTest conn
    , testCase "Delete stream" $ deleteStreamTest conn
    , testCase "Transaction" $ transactionTest conn
    , testCase "Read forward" $ readStreamEventForwardTest conn
    , testCase "Read backward" $ readStreamEventBackwardTest conn
    , testCase "Real $all forward" $ readAllEventsForwardTest conn
    , testCase "Real $all backward" $ readAllEventsBackwardTest conn
    , testCase "Subscription test" $ subscribeTest conn
    , testCase "Subscription from test" $ subscribeFromTest conn
    , testCase "Set Stream Metadata" $ setStreamMetadataTest conn
    , testCase "Get Stream Metadata" $ getStreamMetadataTest conn
    , testCase "Create persistent sub" $ createPersistentTest conn
    , testCase "Update persistent sub" $ updatePersistentTest conn
    , testCase "Delete persistent sub" $ deletePersistentTest conn
    , testCase "Connect persistent sub" $ connectToPersistentTest conn
    , testCase "Shutdown connection" $ shutdownTest conn
    ]

--------------------------------------------------------------------------------
writeEventTest :: Connection -> IO ()
writeEventTest conn = do
    let js  = [ "baz" .= True ]
        evt = createEvent "foo" Nothing $ withJson js

    as <- sendEvent conn "write-event-test" anyVersion evt
    _  <- wait as
    return ()

--------------------------------------------------------------------------------
readEventTest :: Connection -> IO ()
readEventTest conn = do
    let js  = [ "baz" .= True ]
        evt = createEvent "foo" Nothing $ withJson js
    as <- sendEvent conn "read-event-test" anyVersion evt
    _  <- wait as
    bs <- readEvent conn "read-event-test" 0 False
    rs <- wait bs
    case rs of
        ReadSuccess re ->
            case re of
                ReadEvent _ _ revt ->
                    case resolvedEventDataAsJson revt of
                        Just js_evt ->
                            assertEqual "event should match" js js_evt
                        Nothing -> fail "Error when retrieving recorded data"
                _ -> fail "Event not found"
        e -> fail $ "Read failure: " ++ show e

--------------------------------------------------------------------------------
deleteStreamTest :: Connection -> IO ()
deleteStreamTest conn = do
    let js  = [ "baz" .= True ]
        evt = createEvent "foo" Nothing $ withJson js
    _ <- sendEvent conn "delete-stream-test" anyVersion evt >>= wait
    _ <- deleteStream conn "delete-stream-test" anyVersion Nothing
    return ()

--------------------------------------------------------------------------------
transactionTest :: Connection -> IO ()
transactionTest conn = do
    let js  = [ "baz" .= True ]
        evt = createEvent "foo" Nothing $ withJson js
    t  <- startTransaction conn "transaction-test" anyVersion >>= wait
    _  <- transactionWrite t [evt] >>= wait
    rs <- readEvent conn "transaction-test" 0 False >>= wait
    case rs of
        ReadNoStream -> return ()
        e -> fail $ "transaction-test stream is supposed to not exist "
                  ++ show e
    _   <- transactionCommit t >>= wait
    rs2 <- readEvent conn "transaction-test" 0 False >>= wait
    case rs2 of
        ReadSuccess re ->
            case re of
                ReadEvent _ _ revt ->
                    case resolvedEventDataAsJson revt of
                        Just js_evt ->
                            assertEqual "event should match" js js_evt
                        Nothing -> fail "Error when retrieving recorded data"
                _ -> fail "Event not found"
        e -> fail $ "Read failure: " ++ show e

--------------------------------------------------------------------------------
readStreamEventForwardTest :: Connection -> IO ()
readStreamEventForwardTest conn = do
    let jss = [ [ "baz" .= True]
              , [ "foo" .= False]
              , [ "bar" .= True]
              ]
        evts = fmap (createEvent "foo" Nothing . withJson) jss
    _  <- sendEvents conn "read-forward-test" anyVersion evts >>= wait
    rs <- readStreamEventsForward conn "read-forward-test" 0 10 False >>= wait
    case rs of
        ReadSuccess sl -> do
            let jss_evts = catMaybes $ fmap resolvedEventDataAsJson
                                     $ sliceEvents sl
            assertEqual "Events should be equal" jss jss_evts
        e -> fail $ "Read failure: " ++ show e

--------------------------------------------------------------------------------
readStreamEventBackwardTest :: Connection -> IO ()
readStreamEventBackwardTest conn = do
    let jss = [ [ "baz" .= True]
              , [ "foo" .= False]
              , [ "bar" .= True]
              ]
        evts = fmap (createEvent "foo" Nothing . withJson) jss
    _  <- sendEvents conn "read-backward-test" anyVersion evts >>= wait
    rs <- readStreamEventsBackward conn "read-backward-test" 2 10 False >>= wait
    case rs of
        ReadSuccess sl -> do
            let jss_evts = catMaybes $ fmap resolvedEventDataAsJson
                                     $ sliceEvents sl
            assertEqual "Events should be equal" (reverse jss) jss_evts
        e -> fail $ "Read failure: " ++ show e

--------------------------------------------------------------------------------
readAllEventsForwardTest :: Connection -> IO ()
readAllEventsForwardTest conn = do
    sl <- readAllEventsForward conn positionStart 3 False >>= wait
    assertEqual "Events is not empty" False (null $ sliceEvents sl)

--------------------------------------------------------------------------------
readAllEventsBackwardTest :: Connection -> IO ()
readAllEventsBackwardTest conn = do
    sl <- readAllEventsBackward conn positionEnd 3 False >>= wait
    assertEqual "Events is not empty" False (null $ sliceEvents sl)

--------------------------------------------------------------------------------
subscribeTest :: Connection -> IO ()
subscribeTest conn = do
    let jss = [ [ "baz" .= True]
              , [ "foo" .= False]
              , [ "bar" .= True]
              ]
        evts = fmap (createEvent "foo" Nothing . withJson) jss
    sub  <- subscribe conn "subscribe-test" False
    _    <- sendEvents conn "subscribe-test" anyVersion evts >>= wait
    let loop 3 = return []
        loop i = do
            e <- nextEvent sub
            fmap (resolvedEventDataAsJson e:) $ loop (i+1)

    nxt_js <- loop (0 :: Int)
    assertEqual "Events should be equal" jss (catMaybes nxt_js)
    unsubscribe sub
    let action = do
            _ <- nextEvent sub
            return False
    res <- catch action $ \(_ :: SubscriptionClosed) -> return True
    assertBool "Should have raised an exception" res

--------------------------------------------------------------------------------
subscribeFromTest :: Connection -> IO ()
subscribeFromTest conn = do
    let jss = [ [ "1" .= (1 :: Int)]
              , [ "2" .= (2 :: Int)]
              , [ "3" .= (3 :: Int)]
              ]
        jss2 = [ [ "4" .= (4 :: Int)]
               , [ "5" .= (5 :: Int)]
               , [ "6" .= (6 :: Int)]
               ]
        alljss = jss ++ jss2
        evts   = fmap (createEvent "foo" Nothing . withJson) jss
        evts2  = fmap (createEvent "foo" Nothing . withJson) jss2
    _   <- sendEvents conn "subscribe-from-test" anyVersion evts >>= wait
    sub <- subscribeFrom conn "subscribe-from-test" False Nothing (Just 1)
    _   <- sendEvents conn "subscribe-from-test" anyVersion evts2 >>= wait

    let loop [] = do
            m <- nextEventMaybe sub
            case m of
                Just _  -> fail "should not have more events at the point."
                Nothing -> return ()
        loop (x:xs) = do
            evt <- nextEvent sub
            case recordedEventDataAsJson $ resolvedEventOriginal evt of
                Just e | e == x    -> loop xs
                       | otherwise -> fail "Out of order event's appeared."
                _ -> fail "Can't deserialized event"

    loop alljss
    unsubscribe sub
    let action = do
            _ <- nextEvent sub
            return False
    res <- catch action $ \(_ :: SubscriptionClosed) -> return True
    assertBool "Should have raised an exception" res

--------------------------------------------------------------------------------
setStreamMetadataTest :: Connection -> IO ()
setStreamMetadataTest conn = do
    let metadata = buildStreamMetadata $ setCustomProperty "foo" (1 :: Int)
    _ <- setStreamMetadata conn "set-metadata-test" anyVersion metadata >>= wait
    return ()

--------------------------------------------------------------------------------
getStreamMetadataTest :: Connection -> IO ()
getStreamMetadataTest conn = do
    let metadata = buildStreamMetadata $ setCustomProperty "foo" (1 :: Int)
    _ <- setStreamMetadata conn "get-metadata-test" anyVersion metadata >>= wait
    r <- getStreamMetadata conn "get-metadata-test" >>= wait
    case r of
        StreamMetadataResult _ _ m ->
            case getCustomProperty m "foo" of
                Just i -> assertEqual "Should have equal value" (1 :: Int) i
                _      -> fail "Can't find foo property"
        _ -> fail "Stream get-metadata-test doesn't exist"

--------------------------------------------------------------------------------
createPersistentTest :: Connection -> IO ()
createPersistentTest conn = do
    let def = defaultPersistentSubscriptionSettings
    r <- createPersistentSubscription conn "group" "create-sub" def >>= wait
    case r of
        Nothing -> return ()
        Just e  -> fail $ "Exception arised: " ++ show e

--------------------------------------------------------------------------------
updatePersistentTest :: Connection -> IO ()
updatePersistentTest conn = do
    let def = defaultPersistentSubscriptionSettings
    _ <- createPersistentSubscription conn "group" "update-sub" def >>= wait
    r <- updatePersistentSubscription conn "group" "update-sub" def >>= wait
    case r of
        Nothing -> return ()
        Just e  -> fail $ "Exception arised: " ++ show e

--------------------------------------------------------------------------------
deletePersistentTest :: Connection -> IO ()
deletePersistentTest conn = do
    let def = defaultPersistentSubscriptionSettings
    _ <- createPersistentSubscription conn "group" "delete-sub" def >>= wait
    r <- deletePersistentSubscription conn "group" "delete-sub" >>= wait
    case r of
        Nothing -> return ()
        Just e  -> fail $ "Exception arised: " ++ show e

--------------------------------------------------------------------------------
connectToPersistentTest :: Connection -> IO ()
connectToPersistentTest conn = do
    let def = defaultPersistentSubscriptionSettings
        js1 = "baz" .= True
        js2 = "foo" .= True
        jss  = [ js1
               , js2
               ]
        evts = fmap (createEvent "foo" Nothing . withJson) jss
    _   <- createPersistentSubscription conn "group" "connect-sub" def >>= wait
    _   <- sendEvents conn "connect-sub" anyVersion evts >>= wait
    sub <- connectToPersistentSubscription conn "group" "connect-sub" 1
    r   <- nextEvent sub
    case resolvedEventDataAsJson r of
        Just js_evt -> assertEqual "event 1 should match" js1 js_evt
        _           -> fail "Deserialization error"

    notifyEventsProcessed sub [resolvedEventOriginalId r]

    r2 <- nextEvent sub
    case resolvedEventDataAsJson r2 of
        Just js_evt -> assertEqual "event 2 should match" js2 js_evt
        _           -> fail "Deserialization error"

    notifyEventsProcessed sub [resolvedEventOriginalId r2]

    unsubscribe sub
    let action = do
            _ <- nextEvent sub
            return False
    res <- catch action $ \(_ :: SubscriptionClosed) -> return True
    assertBool "Should have raised an exception" res

--------------------------------------------------------------------------------
shutdownTest :: Connection -> IO ()
shutdownTest conn = do
    let js     = "baz" .= True
        evt    = createEvent "foo" Nothing $ withJson js
        action = do
            _ <- sendEvent conn "shutdown-test" anyVersion evt
            return False
    shutdown conn
    waitTillClosed conn
    res <- catch action $ \(_ :: SomeException) -> return True

    assertBool "Should have raised an exception" res
