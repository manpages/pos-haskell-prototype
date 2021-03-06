{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Storage for generic Shared Seed calculation implementation.

module Pos.Ssc.Class.Storage
       (
         -- * Modern
         SscStorageClass (..)
       , SscGlobalQuery
       , SscImpureQuery
       , SscGlobalUpdate
       ) where

import           Serokell.Util.Verify (VerificationRes)
import           Universum

import           Pos.Context.Class    (WithNodeContext)
import           Pos.DB.Class         (MonadDB)
import           Pos.Ssc.Class.Types  (Ssc (..))
import           Pos.Types            (EpochIndex, HeaderHash, NEBlocks, Richmen,
                                       SharedSeed)

----------------------------------------------------------------------------
-- Modern
----------------------------------------------------------------------------

type SscGlobalQuery ssc a =  forall m . (MonadReader (SscGlobalState ssc) m) => m a
type SscGlobalUpdate ssc a = forall m . (MonadState (SscGlobalState ssc) m) => m a

type SscImpureQuery ssc a = forall m. ( MonadReader (SscGlobalState ssc) m
                                       , WithNodeContext ssc m
                                       , MonadIO m) =>
                                       m a

class Ssc ssc => SscStorageClass ssc where
    sscLoadGlobalState :: MonadDB ssc m => HeaderHash ssc -> m (SscGlobalState ssc)

    sscApplyBlocksM :: NEBlocks ssc -> SscGlobalUpdate ssc ()

    -- | Rollback application of blocks.
    sscRollbackM :: NEBlocks ssc -> SscGlobalUpdate ssc ()

    -- | Verify Ssc-related predicates of block sequence which is
    -- about to be applied. It should check that SSC payload will be
    -- consistent if this blocks are applied (after possible rollback
    -- if first argument isn't zero).
    sscVerifyBlocksM :: Bool -> Richmen -> NEBlocks ssc -> SscGlobalQuery ssc VerificationRes

    sscCalculateSeedM :: EpochIndex ->
                         SscGlobalQuery ssc (Either (SscSeedError ssc) SharedSeed)
