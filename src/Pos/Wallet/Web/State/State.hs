{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TypeFamilies    #-}

module Pos.Wallet.Web.State.State
       ( WalletState
       , MonadWalletWebDB (..)
       , WebWalletModeDB
       , openState
       , openMemState
       , closeState

       -- * Getters
       , getWalletMetas
       , getWalletMeta
       , getTxMeta
       , getWalletHistory

       -- * Setters
       , createWallet
       , setWalletMeta
       , setWalletTransactionMeta
       , setWalletHistory
       , addOnlyNewTxMeta
       , removeWallet
       ) where

import           Data.Acid                    (EventResult, EventState, QueryEvent,
                                               UpdateEvent)
import           Universum

import           Pos.Wallet.Web.ClientTypes   (CAddress, CTxId, CTxMeta, CWalletMeta)
import           Pos.Wallet.Web.State.Acidic  (WalletState, closeState, openMemState,
                                               openState)
import           Pos.Wallet.Web.State.Acidic  as A
import           Pos.Wallet.Web.State.Storage (WalletStorage)

-- | MonadWalletWebDB stands for monad which is able to get web wallet state
class Monad m => MonadWalletWebDB m where
    getWalletWebState :: m WalletState

-- | Instances for common transformers
instance MonadWalletWebDB m => MonadWalletWebDB (ReaderT r m) where
    getWalletWebState = lift getWalletWebState

instance MonadWalletWebDB m => MonadWalletWebDB (StateT s m) where
    getWalletWebState = lift getWalletWebState

-- | Constraint for working with web wallet DB
type WebWalletModeDB m = (MonadWalletWebDB m, MonadIO m)

queryDisk
    :: (EventState event ~ WalletStorage, QueryEvent event, WebWalletModeDB m)
    => event -> m (EventResult event)
queryDisk e = getWalletWebState >>= flip A.query e

updateDisk
    :: (EventState event ~ WalletStorage, UpdateEvent event, WebWalletModeDB m)
    => event -> m (EventResult event)
updateDisk e = getWalletWebState >>= flip A.update e

getWalletMetas :: WebWalletModeDB m => m [CWalletMeta]
getWalletMetas = queryDisk A.GetWalletMetas

getWalletMeta :: WebWalletModeDB m => CAddress -> m (Maybe CWalletMeta)
getWalletMeta = queryDisk . A.GetWalletMeta

getTxMeta :: WebWalletModeDB m => CAddress -> CTxId -> m (Maybe CTxMeta)
getTxMeta addr = queryDisk . A.GetTxMeta addr

getWalletHistory :: WebWalletModeDB m => CAddress -> m (Maybe [CTxMeta])
getWalletHistory = queryDisk . A.GetWalletHistory

createWallet :: WebWalletModeDB m => CAddress -> CWalletMeta -> m ()
createWallet addr = updateDisk . A.CreateWallet addr

setWalletMeta :: WebWalletModeDB m => CAddress -> CWalletMeta -> m ()
setWalletMeta addr = updateDisk . A.SetWalletMeta addr

setWalletTransactionMeta :: WebWalletModeDB m => CAddress -> CTxId -> CTxMeta -> m ()
setWalletTransactionMeta addr ctxId = updateDisk . A.SetWalletTransactionMeta addr ctxId

setWalletHistory :: WebWalletModeDB m => CAddress -> [(CTxId, CTxMeta)] -> m ()
setWalletHistory addr = updateDisk . A.SetWalletHistory addr

addOnlyNewTxMeta :: WebWalletModeDB m => CAddress -> CTxId -> CTxMeta -> m ()
addOnlyNewTxMeta addr ctxId = updateDisk . A.AddOnlyNewTxMeta addr ctxId

removeWallet :: WebWalletModeDB m => CAddress -> m ()
removeWallet = updateDisk . A.RemoveWallet
