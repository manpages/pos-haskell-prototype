{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Interface to Blocks DB.

module Pos.DB.Block
       ( getBlock
       , getBlockHeader
       , getStoredBlock
       , getUndo
       , getNextHash
       , setBlockInMainChain
       , isBlockInMainChain

       , deleteBlock
       , putBlock
       , loadBlocksWithUndoWhile
       , loadBlocksWhile
       , loadHeadersWhile

       , prepareBlockDB
       ) where

import           Control.Lens        ((^.))
import           Data.ByteArray      (convert)
import           Formatting          (sformat, (%))
import           Universum

import           Pos.Binary.Class    (Bi)
import           Pos.Binary.DB       ()
import           Pos.Crypto          (Hash, shortHashF)
import           Pos.DB.Class        (MonadDB, getBlockDB)
import           Pos.DB.Error        (DBError (..))
import           Pos.DB.Functions    (rocksDelete, rocksGetBi, rocksPutBi)
import           Pos.DB.Types        (StoredBlock (..))
import           Pos.Ssc.Class.Types (Ssc)
import           Pos.Types           (Block, BlockHeader, GenesisBlock, HasPrevBlock,
                                      HeaderHash, Undo (..), genesisHash, headerHash,
                                      prevBlockL)
import qualified Pos.Types           as T


-- | Get StoredBlock by hash from Block DB.
getStoredBlock
    :: (Ssc ssc, MonadDB ssc m)
    => HeaderHash ssc -> m (Maybe (StoredBlock ssc))
getStoredBlock = getBi . blockKey

-- | Get block with given hash from Block DB.
getBlock
    :: (Ssc ssc, MonadDB ssc m)
    => HeaderHash ssc -> m (Maybe (Block ssc))
getBlock = fmap (fmap sbBlock) . getStoredBlock

-- | Returns header of block that was requested from Block DB.
getBlockHeader
    :: (Ssc ssc, MonadDB ssc m)
    => HeaderHash ssc -> m (Maybe (BlockHeader ssc))
getBlockHeader h = fmap T.getBlockHeader <$> getBlock h

-- | Gets hash of the next block in the blockchain
getNextHash
    :: (MonadDB ssc m)
    => HeaderHash ssc -> m (Maybe (HeaderHash ssc))
getNextHash = getBi . ptrKey

-- | Sets block's inMainChain flag to supplied value. Does nothing if
-- block wasn't found.
setBlockInMainChain
    :: (Ssc ssc, MonadDB ssc m)
    => HeaderHash ssc -> Bool -> m ()
setBlockInMainChain h inMainChain =
    whenJustM (getBlock h) $ \blk ->
        putBi (blockKey h) $ StoredBlock blk inMainChain

-- | Get block with given hash from Block DB.
isBlockInMainChain
    :: (Ssc ssc, MonadDB ssc m)
    => HeaderHash ssc -> m Bool
isBlockInMainChain = fmap (maybe False sbInMain) . getStoredBlock

-- | Get undo data for block with given hash from Block DB.
getUndo
    :: (MonadDB ssc m)
    => HeaderHash ssc -> m (Maybe Undo)
getUndo = getBi . undoKey

-- | Put given block, its metadata and Undo data into Block DB.
putBlock
    :: (Ssc ssc, MonadDB ssc m)
    => Undo -> Bool -> Block ssc -> m ()
putBlock undo inMainChain blk = do
    let h = headerHash blk
        ph = blk ^. prevBlockL
    putBi
        (blockKey h)
        StoredBlock
        { sbBlock = blk
        , sbInMain = inMainChain
        }
    putBi (undoKey h) undo
    -- Save forward link to enable forward traversal
    putBi (ptrKey ph) h

deleteBlock :: (MonadDB ssc m) => HeaderHash ssc -> m ()
deleteBlock = delete . blockKey

getBlockWithUndo :: (Ssc ssc, MonadDB ssc m)
                 => HeaderHash ssc -> m (Block ssc, Undo)
getBlockWithUndo hash =
    maybe (throwM $ DBMalformed $ sformat errFmt hash) pure =<<
    (liftA2 (,) <$> getBlock hash <*> getUndo hash)
  where
    errFmt =
        ("getBlockWithUndo: no block or undo with such HeaderHash: " %shortHashF)

loadDataWhile :: (Monad m, HasPrevBlock a b)
              => (Hash b -> m a)
              -> (a -> Int -> Bool)
              -> Hash b
              -> m [a]
loadDataWhile getter predicate start = doIt 0 start
  where
    doIt depth h = do
        d <- getter h
        let prev = d ^. prevBlockL
        if predicate d depth && (prev /= genesisHash)
            then (d:) <$> doIt (succ depth) prev
            else pure []

-- | Load blocks starting from block with header hash equals @hash@
-- and while @predicate@ is true.  The head of returned list is the
-- youngest block.
loadBlocksWithUndoWhile
    :: (Ssc ssc, MonadDB ssc m)
    => (Block ssc -> Int -> Bool) -> HeaderHash ssc -> m [(Block ssc, Undo)]
loadBlocksWithUndoWhile predicate =
    loadDataWhile getBlockWithUndo (predicate . fst)

loadBlocksWhile
    :: (Ssc ssc, MonadDB ssc m)
    => (Block ssc -> Int -> Bool) -> HeaderHash ssc -> m [Block ssc]
loadBlocksWhile =
    loadDataWhile (getBlock >=> maybe (panic "No block with such header hash") pure)

-- | Takes a starting header hash and queries blockchain while some
-- condition is true or parent wasn't found. Returns headers newest
-- first.
loadHeadersWhile
    :: forall ssc m.
       (MonadDB ssc m, Ssc ssc)
    => HeaderHash ssc
    -> (BlockHeader ssc -> Int -> Bool)
    -> m [BlockHeader ssc]
loadHeadersWhile startHHash cond = loadHeadersWhileDo startHHash 0
  where
    errFmt =
        ("loadHeadersWhile: no header parent with such HeaderHash: " %shortHashF)
    loadHeadersWhileDo :: HeaderHash ssc -> Int -> m [BlockHeader ssc]
    loadHeadersWhileDo curH _ | curH == genesisHash = pure []
    loadHeadersWhileDo curH depth = do
        curHeaderM <- getBlockHeader curH
        case curHeaderM of
            Nothing -> throwM $ DBMalformed $ sformat errFmt curH
            Just curHeader
                | cond curHeader depth ->
                  (curHeader :) <$> loadHeadersWhileDo (curHeader ^. prevBlockL) (succ depth)
                | otherwise -> pure []

----------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------

prepareBlockDB
    :: forall ssc m.
       (Ssc ssc, MonadDB ssc m)
    => GenesisBlock ssc -> m ()
prepareBlockDB = putBlock (Undo [] []) True . Left

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

getBi
    :: (MonadDB ssc m, Bi v)
    => ByteString -> m (Maybe v)
getBi k = rocksGetBi k =<< getBlockDB

putBi
    :: (MonadDB ssc m, Bi v)
    => ByteString -> v -> m ()
putBi k v = rocksPutBi k v =<< getBlockDB

delete :: (MonadDB ssc m) => ByteString -> m ()
delete k = rocksDelete k =<< getBlockDB

blockKey :: HeaderHash ssc -> ByteString
blockKey h = "b" <> convert h

undoKey :: HeaderHash ssc -> ByteString
undoKey h = "u" <> convert h

ptrKey :: HeaderHash ssc -> ByteString
ptrKey h = "p" <> convert h
