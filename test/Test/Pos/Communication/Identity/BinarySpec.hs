-- | This module tests Binary instances for Pos.Communication types

module Test.Pos.Communication.Identity.BinarySpec
       ( spec
       ) where

import           Test.Hspec        (Spec, describe)
import           Universum

import qualified Pos.Communication as C
import qualified Pos.Delegation    as D

import           Test.Pos.Util     (binaryTest)

spec :: Spec
spec = describe "Communication" $ do
    describe "Bi instances" $ do
        binaryTest @C.SysStartRequest
        binaryTest @C.SysStartResponse
        binaryTest @D.SendProxySK
        binaryTest @D.ConfirmProxySK
        binaryTest @D.CheckProxySKConfirmed
        binaryTest @D.CheckProxySKConfirmedRes
