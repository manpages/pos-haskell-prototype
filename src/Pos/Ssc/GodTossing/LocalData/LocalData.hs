{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE Rank2Types           #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}

-- | This module defines methods which operate on GtLocalData.

module Pos.Ssc.GodTossing.LocalData.LocalData
       (
         localOnNewSlot
       , sscIsDataUseful
       , sscProcessMessage
         -- * Instances
         -- ** instance SscLocalDataClass SscGodTossing
       ) where

import           Control.Lens                         (Getter, at, use, view, (%=), (.=))
import           Data.Containers                      (ContainerKey,
                                                       SetContainer (notMember))
import qualified Data.HashMap.Strict                  as HM
import qualified Data.HashSet                         as HS
import           Serokell.Util.Verify                 (isVerSuccess)
import           Universum

import           Pos.Binary.Class                     (Bi)
import           Pos.Crypto                           (Share)
import           Pos.Ssc.Class.LocalData              (LocalQuery, LocalUpdate,
                                                       SscLocalDataClass (..))
import           Pos.Ssc.Extra.MonadLD                (MonadSscLD)
import           Pos.Ssc.GodTossing.Functions         (checkCommShares,
                                                       checkOpeningMatchesCommitment,
                                                       checkShares, isCommitmentIdx,
                                                       isOpeningIdx, isSharesIdx,
                                                       verifySignedCommitment)
import           Pos.Ssc.GodTossing.LocalData.Helpers (GtState, gtGlobalCertificates,
                                                       gtGlobalCommitments,
                                                       gtGlobalOpenings, gtGlobalShares,
                                                       gtLastProcessedSlot,
                                                       gtLocalCertificates,
                                                       gtLocalCommitments,
                                                       gtLocalOpenings, gtLocalShares,
                                                       gtRunModify, gtRunRead)
import           Pos.Ssc.GodTossing.LocalData.Types   (ldCertificates, ldCommitments,
                                                       ldOpenings, ldShares)
import           Pos.Ssc.GodTossing.Types             (GtGlobalState (..), GtPayload (..),
                                                       SscBi, SscGodTossing)
import           Pos.Ssc.GodTossing.Types.Base        (Commitment, Opening,
                                                       SignedCommitment, VssCertificate,
                                                       VssCertificatesMap, vcVssKey)
import           Pos.Ssc.GodTossing.Types.Message     (GtMsgContents (..), GtMsgTag (..))
import qualified Pos.Ssc.GodTossing.VssCertData       as VCD
import           Pos.Types                            (Richmen, SlotId (..),
                                                       StakeholderId)
import           Pos.Util                             (AsBinary, diffDoubleMap, getKeys,
                                                       readerToState)

instance SscBi => SscLocalDataClass SscGodTossing where
    sscGetLocalPayloadQ = getLocalPayload
    sscApplyGlobalStateU = applyGlobal

type LDQuery a = forall m .  MonadReader GtState m => m a
type LDUpdate a = forall m . MonadState GtState m  => m a

----------------------------------------------------------------------------
-- Apply Global State
----------------------------------------------------------------------------
applyGlobal :: GtGlobalState -> LocalUpdate SscGodTossing ()
applyGlobal globalData = do
    let globalCommitments = _gsCommitments globalData
        globalOpenings = _gsOpenings globalData
        globalShares = _gsShares globalData
        globalCert = _gsVssCertificates globalData
    ldCommitments  %= (`HM.difference` globalCommitments)
    ldOpenings  %= (`HM.difference` globalOpenings)
    ldShares  %= (`diffDoubleMap` globalShares)
    ldCertificates  %= (`HM.difference` (VCD.certs globalCert))

----------------------------------------------------------------------------
-- Get Local Payload
----------------------------------------------------------------------------
getLocalPayload :: SlotId -> LocalQuery SscGodTossing GtPayload
getLocalPayload SlotId{..} =
    (if isCommitmentIdx siSlot then
        CommitmentsPayload <$> view ldCommitments
    else if isOpeningIdx siSlot then
        OpeningsPayload <$> view ldOpenings
    else if isSharesIdx siSlot then
        SharesPayload <$> view ldShares
    else
        pure CertificatesPayload)
    <*> view ldCertificates

----------------------------------------------------------------------------
-- Process New Slot
----------------------------------------------------------------------------
-- | Clean-up some data when new slot starts.
localOnNewSlot
    :: MonadSscLD SscGodTossing m
    => SlotId -> m ()
localOnNewSlot = gtRunModify . localOnNewSlotU

localOnNewSlotU :: SlotId -> LDUpdate ()
localOnNewSlotU si@SlotId {siSlot = slotIdx} = do
    unless (isCommitmentIdx slotIdx) $ gtLocalCommitments .= mempty
    unless (isOpeningIdx slotIdx) $ gtLocalOpenings .= mempty
    unless (isSharesIdx slotIdx) $ gtLocalShares .= mempty
    gtLastProcessedSlot .= si

----------------------------------------------------------------------------
-- Check knowledge of data
----------------------------------------------------------------------------

-- CHECK: @sscIsDataUseful
-- #sscIsDataUsefulQ

-- | Check whether SSC data with given tag and public key can be added
-- to local data.
sscIsDataUseful
    :: MonadSscLD SscGodTossing m
    => GtMsgTag -> StakeholderId -> m Bool
sscIsDataUseful tag = gtRunRead . sscIsDataUsefulQ tag

-- CHECK: @sscIsDataUsefulQ
-- | Check whether SSC data with given tag and public key can be added
-- to local data.
sscIsDataUsefulQ :: GtMsgTag -> StakeholderId -> LDQuery Bool
sscIsDataUsefulQ CommitmentMsg =
    sscIsDataUsefulImpl gtLocalCommitments gtGlobalCommitments
sscIsDataUsefulQ OpeningMsg =
    sscIsDataUsefulSetImpl gtLocalOpenings gtGlobalOpenings
sscIsDataUsefulQ SharesMsg =
    sscIsDataUsefulSetImpl gtLocalShares gtGlobalShares
sscIsDataUsefulQ VssCertificateMsg = sscIsCertUsefulImpl
  where
    sscIsCertUsefulImpl addr = do
        loc <- view gtLocalCertificates
        glob <- view gtGlobalCertificates
        lpe <- siEpoch <$> view gtLastProcessedSlot
        if addr `HM.member` loc then pure False
        else pure $ maybe True (== lpe) (VCD.lookupExpiryEpoch addr glob)

type MapGetter a = Getter GtState (HashMap StakeholderId a)
type SetGetter set = Getter GtState set

sscIsDataUsefulImpl :: MapGetter a
                    -> MapGetter a
                    -> StakeholderId
                    -> LDQuery Bool
sscIsDataUsefulImpl localG globalG addr =
    (&&) <$>
        (notMember addr <$> view globalG) <*>
        (notMember addr <$> view localG)

sscIsDataUsefulSetImpl
    :: (SetContainer set, ContainerKey set ~ StakeholderId)
    => MapGetter a -> SetGetter set -> StakeholderId -> LDQuery Bool
sscIsDataUsefulSetImpl localG globalG addr =
    (&&) <$>
        (notMember addr <$> view localG) <*>
        (notMember addr <$> view globalG)

----------------------------------------------------------------------------
-- Ssc Process Message
----------------------------------------------------------------------------
-- | Process message and save it if needed. Result is whether message
-- has been actually added.
sscProcessMessage ::
       (MonadSscLD SscGodTossing m, SscBi)
    => Richmen -> GtMsgContents -> StakeholderId -> m Bool
sscProcessMessage richmen msg = gtRunModify . sscProcessMessageU richmen msg

sscProcessMessageU :: SscBi => Richmen -> GtMsgContents -> StakeholderId -> LDUpdate Bool
sscProcessMessageU richmen (MCCommitment comm) addr = processCommitment richmen addr comm
sscProcessMessageU _ (MCOpening open)          addr = processOpening addr open
sscProcessMessageU _ (MCShares shares)         addr = processShares addr shares
sscProcessMessageU _ (MCVssCertificate cert)   addr = processVssCertificate addr cert

processCommitment
    :: Bi Commitment
    => Richmen
    -> StakeholderId
    -> SignedCommitment
    -> LDUpdate Bool
processCommitment richmen addr c = do
    certs <- VCD.certs <$> use gtGlobalCertificates
    let participants = certs `HM.intersection`
                      (HM.fromList $ zip (toList richmen) (repeat ()))
    let vssPublicKeys = HS.fromList $ map vcVssKey $ toList participants
    let checks epochIndex vssCerts =
            [ not . HM.member addr <$> view gtGlobalCommitments
            , not . HM.member addr <$> view gtLocalCommitments
            , pure $ addr `HM.member` vssCerts
            , pure . isVerSuccess $ verifySignedCommitment addr epochIndex c
            , pure $ checkCommShares vssPublicKeys c
            ]
    epochIdx <- siEpoch <$> use gtLastProcessedSlot
    ok <- readerToState $ andM $ checks epochIdx certs
    ok <$ when ok (gtLocalCommitments %= HM.insert addr c)

processOpening :: StakeholderId -> Opening -> LDUpdate Bool
processOpening addr o = do
    ok <- readerToState $ andM checks
    ok <$ when ok (gtLocalOpenings %= HM.insert addr o)
  where
    checkAbsence = sscIsDataUsefulSetImpl gtLocalOpenings gtGlobalOpenings
    checks = [checkAbsence addr, matchOpening addr o]

-- Match opening to commitment from globalCommitments
matchOpening :: StakeholderId -> Opening -> LDQuery Bool
matchOpening addr opening =
    flip checkOpeningMatchesCommitment (addr, opening) <$> view gtGlobalCommitments

processShares :: StakeholderId
              -> HashMap StakeholderId (AsBinary Share)
              -> LDUpdate Bool
processShares addr s
    | null s = pure False
    | otherwise = do
        certs <- VCD.certs <$> use gtGlobalCertificates
        -- TODO: we accept shares that we already have (but don't add them to
        -- local shares) because someone who sent us those shares might not be
        -- aware of the fact that they are already in the blockchain. On the
        -- other hand, now nodes can send us huge spammy messages and we can't
        -- ban them for that. On the third hand, is this a concern?
        globalSharesPKForPK <- getKeys . HM.lookupDefault mempty addr <$> use gtGlobalShares
        localSharesForPk <- HM.lookupDefault mempty addr <$> use gtLocalShares
        let s' = s `HM.difference` (HS.toMap globalSharesPKForPK)
        let newLocalShares = localSharesForPk `HM.union` s'
        -- Note: size is O(n), but union is also O(n + m), so
        -- it doesn't matter.
        let checks =
              [ pure (HM.size newLocalShares /= HM.size localSharesForPk)
              , readerToState $ checkSharesLastVer certs addr s
              ]
        ok <- andM checks
        ok <$ when ok (gtLocalShares . at addr .= Just newLocalShares)

-- CHECK: #checkShares
checkSharesLastVer
    :: VssCertificatesMap
    -> StakeholderId
    -> HashMap StakeholderId (AsBinary Share)
    -> LDQuery Bool
checkSharesLastVer certs addr shares =
    (\comms openings -> checkShares comms openings certs addr shares) <$>
    view gtGlobalCommitments <*>
    view gtGlobalOpenings

processVssCertificate :: StakeholderId -> VssCertificate -> LDUpdate Bool
processVssCertificate addr c = do
    ok <- readerToState (sscIsDataUsefulQ VssCertificateMsg addr)
    ok <$ when ok (gtLocalCertificates %= HM.insert addr c)
