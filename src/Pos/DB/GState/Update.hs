{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Part of GState DB which stores data necessary for update system.

module Pos.DB.GState.Update
       (
         -- * Getters
         getLastPV

         -- * Initialization
       , prepareGStateUS
       ) where

import           Universum

import           Pos.DB.Class         (MonadDB)
import           Pos.DB.Error         (DBError (DBMalformed))
import           Pos.DB.GState.Common (getBi, putBi)
import           Pos.Genesis          (genesisProtocolVersion)
import           Pos.Types            (ProtocolVersion)
import           Pos.Util             (maybeThrow)

----------------------------------------------------------------------------
-- Getters
----------------------------------------------------------------------------

-- | Get last approved protocol version.
getLastPV :: MonadDB ssc m => m ProtocolVersion
getLastPV = maybeThrow (DBMalformed msg) =<< getLastPVMaybe
  where
    msg =
        "Update System part of GState DB is not initialized (last PV is missing)"

----------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------

prepareGStateUS
    :: forall ssc m.
       MonadDB ssc m
    => m ()
prepareGStateUS = unlessM isInitialized $ do
    putBi lastPVKey genesisProtocolVersion

isInitialized :: MonadDB ssc m => m Bool
isInitialized = isJust <$> getLastPVMaybe

----------------------------------------------------------------------------
-- Keys ('us' prefix stands for Update System)
----------------------------------------------------------------------------

lastPVKey :: ByteString
lastPVKey = "us/last-protocol"

----------------------------------------------------------------------------
-- Details
----------------------------------------------------------------------------

getLastPVMaybe :: MonadDB ssc m => m (Maybe ProtocolVersion)
getLastPVMaybe = getBi lastPVKey