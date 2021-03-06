{-# LANGUAGE ViewPatterns #-}

-- | Messages used for communication in GodTossing SSC.

module Pos.Ssc.GodTossing.Types.Message
       ( GtMsgTag (..)
       , isGoodSlotForTag
       , isGoodSlotIdForTag
       , GtMsgContents (..)
       , msgContentsTag
       ) where

import qualified Data.Text.Buildable           as Buildable
import           Universum

import           Pos.Ssc.GodTossing.Functions  (isCommitmentId, isCommitmentIdx,
                                                isOpeningId, isOpeningIdx, isSharesId,
                                                isSharesIdx)
import           Pos.Ssc.GodTossing.Types.Base (InnerSharesMap, Opening, SignedCommitment,
                                                VssCertificate)
import           Pos.Types                     (LocalSlotIndex, SlotId)
import           Pos.Util                      (NamedMessagePart (..))

-- | Tag associated with message.
data GtMsgTag
    = CommitmentMsg
    | OpeningMsg
    | SharesMsg
    | VssCertificateMsg
    deriving (Show, Eq, Generic)

instance NamedMessagePart GtMsgTag where
    nMessageName _     = "Gt tag"

instance NamedMessagePart GtMsgContents where
    nMessageName _     = "Gt contents"

instance Buildable GtMsgTag where
    build CommitmentMsg     = "commitment"
    build OpeningMsg        = "opening"
    build SharesMsg         = "shares"
    build VssCertificateMsg = "VSS certificate"

isGoodSlotForTag :: GtMsgTag -> LocalSlotIndex -> Bool
isGoodSlotForTag CommitmentMsg     = isCommitmentIdx
isGoodSlotForTag OpeningMsg        = isOpeningIdx
isGoodSlotForTag SharesMsg         = isSharesIdx
isGoodSlotForTag VssCertificateMsg = const True

isGoodSlotIdForTag :: GtMsgTag -> SlotId -> Bool
isGoodSlotIdForTag CommitmentMsg     = isCommitmentId
isGoodSlotIdForTag OpeningMsg        = isOpeningId
isGoodSlotIdForTag SharesMsg         = isSharesId
isGoodSlotIdForTag VssCertificateMsg = const True

-- [CSL-203]: this model assumes that shares and commitments are
-- always sent as a single message, it allows to identify such
-- messages using only Address.

-- | Data message. Can be used to send actual data.
data GtMsgContents
    = MCCommitment !SignedCommitment
    | MCOpening !Opening
    | MCShares !InnerSharesMap
    | MCVssCertificate !VssCertificate
    deriving (Show, Eq, Generic)

instance Buildable GtMsgContents where
    build (msgContentsTag -> tag) = Buildable.build tag <> " contents"

-- | GtMsgTag appropriate for given DataMsg.
msgContentsTag :: GtMsgContents -> GtMsgTag
msgContentsTag (MCCommitment _)     = CommitmentMsg
msgContentsTag (MCOpening _)        = OpeningMsg
msgContentsTag (MCShares _)         = SharesMsg
msgContentsTag (MCVssCertificate _) = VssCertificateMsg
