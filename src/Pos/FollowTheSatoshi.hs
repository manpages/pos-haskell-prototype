{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Everything related to /follow-the-satoshi/ procedure.

module Pos.FollowTheSatoshi
       ( followTheSatoshi
       , followTheSatoshiM
       ) where

import           Data.List.NonEmpty (NonEmpty, fromList)
import           Universum

import           Pos.Constants      (epochSlots)
import           Pos.Crypto         (deterministic, randomNumber)
import           Pos.Types.Coin     (coinToInteger, sumCoins, unsafeAddCoin)
import           Pos.Types.Types    (Coin, SharedSeed (..), StakeholderId, TxOutAux, Utxo,
                                     mkCoin, txOutStake)
import           Pos.Util.Iterator  (ListHolder, MonadIterator (..), runListHolder)

-- | A version of 'followTheSatoshi' that uses an iterator over 'TxOut's
-- instead of 'Utxo'.
followTheSatoshiM
    :: forall m. MonadIterator m TxOutAux
    => SharedSeed -> Coin -> m (NonEmpty StakeholderId)
followTheSatoshiM _ totalCoins
    | totalCoins == mkCoin 0 = panic "followTheSatoshiM: nobody has any stake"
followTheSatoshiM (SharedSeed seed) totalCoins = do
    res <- findLeaders (sortOn fst $ zip coinIndices [1..]) (mkCoin 0) []
    pure . fromList . map fst . sortOn snd $ res
  where
    coinIndices :: [Coin]
    -- There won't be overflow because totalCoins fits in 64 bits
    coinIndices = map (mkCoin . fromInteger . (+1)) $
              deterministic seed $
              replicateM epochSlots (randomNumber (coinToInteger totalCoins))

    findLeaders
        :: [(Coin, Int)]
        -> Coin
        -> [(StakeholderId, Coin)] -- buffer of stake; we need it
                                   -- because each TxOut can expand
                                   -- into several pieces of stake
                                   -- and we need some buffer to
                                   -- iterate over them
        -> m [(StakeholderId, Int)]
    -- We found all coins we wanted to find
    findLeaders [] _ _ = pure []
    -- We ran out of items in the buffer so we take a new output
    -- and refill the buffer
    findLeaders cs sm [] = do
        mbOut <- curItem
        stake <- case mbOut of
            Nothing -> panic "followTheSatoshiM: indices out of range"
            Just out -> do _ <- nextItem @_ @TxOutAux
                           return (txOutStake out)
        findLeaders cs sm stake
    -- We check whether `c` is covered by current item in the buffer
    findLeaders (c:cs) sm buf@((adr, val):bufRest)
        | sm' >= fst c =
            ((adr, snd c):) <$> findLeaders cs sm buf
        | otherwise =
            findLeaders (c:cs) sm' bufRest
      where
        sm' = unsafeAddCoin sm val

-- | Choose several random stakeholders (specifically, their amount is
-- currently hardcoded in 'Pos.Constants.epochSlots').
--
-- The probability that a stakeholder will be chosen is proportional to the
-- number of coins this stakeholder holds. The same stakeholder can be picked
-- more than once.
--
-- How the algorithm works: we sort all unspent outputs in a deterministic
-- way (lexicographically) and have an ordered sequence of pairs
-- @(StakeholderId, Coin)@. Then we choose several random 'i's between 1 and
-- amount of satoshi in the system; to find owner of 'i'th coin we find the
-- lowest x such that sum of all coins in this list up to 'i'th is not less
-- than 'i' (and then 'x'th address is the owner).
--
-- With P2SH addresses, we don't know who is going to end up with funds sent
-- to them. Therefore, P2SH addresses can contain 'addrDestination' which
-- specifies which addresses should count as “owning” funds for the purposes
-- of follow-the-satoshi.
followTheSatoshi :: SharedSeed -> Utxo -> NonEmpty StakeholderId
followTheSatoshi seed utxo
    | null outputs =
          panic "followTheSatoshi: utxo is empty"
    | totalCoins > coinToInteger (maxBound @Coin) =
          panic "followTheSatoshi: totalCoins exceeds Word64"
    | otherwise =
          runListHolder
              (followTheSatoshiM @(ListHolder TxOutAux) seed
                   (mkCoin (fromInteger totalCoins)))
              outputs
  where
    outputs = toList utxo
    totalCoins = sumCoins (map snd (concatMap txOutStake outputs))
