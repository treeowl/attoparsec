{-# LANGUAGE BangPatterns #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Data.ParserCombinators.Attoparsec.FastSet
-- Copyright   :  Bryan O'Sullivan 2008
-- License     :  BSD3
-- 
-- Maintainer  :  bos@serpentine.com
-- Stability   :  experimental
-- Portability :  unknown
--
-- Fast set membership tests for 'Word8' and 8-bit 'Char' values.  The
-- set representation is unboxed for efficiency.  For sets of fewer
-- than 32 elements, we test for membership using a binary search.
-- For larger sets, we use a lookup table.
-- 
-----------------------------------------------------------------------------
module Data.ParserCombinators.Attoparsec.FastSet
    (
    -- * Data type
      FastSet
    -- * Construction
    , fromList
    , set
    -- * Lookup
    , memberChar
    , memberWord8
    -- * Debugging
    , fromSet
    ) where

import Data.Bits ((.&.), (.|.), shiftL, shiftR)
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString as B
import qualified Data.ByteString.Internal as I
import qualified Data.ByteString.Unsafe as U
import Data.Word (Word8)
import Foreign.Storable (peekByteOff, pokeByteOff)

data FastSet = Sorted { fromSet :: {-# UNPACK #-} !B.ByteString }
             | Table  { fromSet :: {-# UNPACK #-} !B.ByteString }
    deriving (Eq, Ord)

instance Show FastSet where
    show (Sorted s) = "FastSet Sorted " ++ show (B8.unpack s)
    show (Table _) = "FastSet Table"

-- | The lower bound on the size of a lookup table.  We choose this to
-- balance table density against performance.
tableCutoff :: Int
tableCutoff = 8

-- | Create a set.
set :: B.ByteString -> FastSet
set s | B.length s < tableCutoff = Sorted . B.sort $ s
      | otherwise                = Table . mkTable $ s

fromList :: [Word8] -> FastSet
fromList = set . B.pack

index :: Int -> (Int, Word8)
index i = (i `shiftR` 3, 1 `shiftL` (i .&. 7))

-- | Check the set for membership.
memberWord8 :: Word8 -> FastSet -> Bool
memberWord8 w (Table t)  =
    let (byte,bit) = index (fromIntegral w)
    in U.unsafeIndex t byte .&. bit /= 0
memberWord8 w (Sorted s) = search 0 (B.length s - 1)
    where search lo hi
              | hi < lo = False
              | otherwise =
                  let mid = (lo + hi) `div` 2
                  in case compare w (U.unsafeIndex s mid) of
                       GT -> search (mid + 1) hi
                       LT -> search lo (mid - 1)
                       _ -> True

-- | Check the set for membership.  Only works with 8-bit characters:
-- characters above code point 255 will give wrong answers.
memberChar :: Char -> FastSet -> Bool
memberChar c = memberWord8 (I.c2w c)

mkTable :: B.ByteString -> B.ByteString
mkTable s = I.unsafeCreate 32 $ \t -> do
            I.memset t 0 32
            U.unsafeUseAsCStringLen s $ \(p, l) ->
              let loop n | n == l = return ()
                         | otherwise = do
                    c <- peekByteOff p n :: IO Word8
                    let (byte,bit) = index (fromIntegral c)
                    prev <- peekByteOff t byte :: IO Word8
                    pokeByteOff t byte (prev .|. bit)
                    loop (n + 1)
              in loop 0