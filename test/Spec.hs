-- test/Spec.hs

import Test.Hspec

sub1 :: Int -> Int
sub1 x = x - 1

main :: IO ()
main = hspec $ do
  describe "sub1" $ do
    it "produces known value for counter 0" $ do
      sub1 0 `shouldBe` -1
