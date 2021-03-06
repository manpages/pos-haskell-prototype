-- | 'Arbitrary' unsafe instances for 'SlotId' and 'TxOut'.

module Pos.Types.Arbitrary.Unsafe () where

import           Universum

import           Pos.Crypto.Arbitrary.Unsafe ()
import           Pos.Types.Types             (Address (..), Coin, EpochIndex (..),
                                              LocalSlotIndex (..), SharedSeed (..),
                                              SlotId (..), TxOut (..), mkCoin)
import           Pos.Util.Arbitrary          (ArbitraryUnsafe (..))

deriving instance ArbitraryUnsafe SharedSeed
deriving instance ArbitraryUnsafe EpochIndex
deriving instance ArbitraryUnsafe LocalSlotIndex

instance ArbitraryUnsafe Coin where
    arbitraryUnsafe = mkCoin <$> arbitraryUnsafe

instance ArbitraryUnsafe Address where
    arbitraryUnsafe = PubKeyAddress <$> arbitraryUnsafe

instance ArbitraryUnsafe SlotId where
    arbitraryUnsafe = SlotId <$> arbitraryUnsafe <*> arbitraryUnsafe

instance ArbitraryUnsafe TxOut where
    arbitraryUnsafe = TxOut <$> arbitraryUnsafe <*> arbitraryUnsafe
