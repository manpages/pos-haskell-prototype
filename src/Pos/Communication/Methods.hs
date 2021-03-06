{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Wrappers on top of communication methods.

module Pos.Communication.Methods
       (
       -- * Sending data into network
         sendToNeighborsSafe
       , sendToNeighborsSafeWithMaliciousEmulation
       ) where

import           Control.TimeWarp.Rpc     (Message)
import           Control.TimeWarp.Timed   (fork_)
import           Universum

import           Pos.Binary.Class         (Bi)
import           Pos.Binary.Communication ()
import           Pos.Binary.Types         ()
import           Pos.Context              (getNodeContext, ncAttackTypes)
import           Pos.DHT.Model            (defaultSendToNeighbors, sendToNeighbors,
                                           sendToNode)
import           Pos.Security             (AttackType (..), shouldIgnoreAddress)
import           Pos.Util                 (logWarningWaitLinear, messageName')
import           Pos.WorkMode             (MinWorkMode, WorkMode)

-- thread and controls how much time action takes.
sendToNeighborsSafeImpl :: (Message r, MinWorkMode ssc m) => (r -> m ()) -> r -> m ()
sendToNeighborsSafeImpl sender msg = do
    let msgName = messageName' msg
    let action = () <$ sender msg
    fork_ $
        logWarningWaitLinear 10 ("Sending " <> msgName <> " to neighbors") action

sendToNeighborsSafe :: forall r m ssc . (Bi r, Message r, MinWorkMode ssc m) => r -> m ()
sendToNeighborsSafe msg = do
    let action :: forall r0 . (Bi r0, Message r0) => r0 -> m ()
        action = void . sendToNeighbors
    --sendToNeighborsSafeImpl action VersionReq
    sendToNeighborsSafeImpl action msg

sendToNeighborsSafeWithMaliciousEmulation
    :: forall r m ssc.
       (Bi r, Message r, WorkMode ssc m)
    => r -> m ()
sendToNeighborsSafeWithMaliciousEmulation msg = do
    cont <- getNodeContext
    -- [CSL-336] Make this parallel
    let sender :: forall r0 . (Bi r0, Message r0) => r0 -> m Int
        sender = if AttackNoBlocks `elem` ncAttackTypes cont
                 then defaultSendToNeighbors sequence (sendToNode' cont)
                 else sendToNeighbors
    --sendToNeighborsSafeImpl (void . sender) VersionReq
    sendToNeighborsSafeImpl (void . sender) msg
  where
    sendToNode' cont addr message =
        unless (shouldIgnoreAddress cont addr) $
            sendToNode addr message
