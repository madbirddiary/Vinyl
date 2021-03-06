module Plotter where

import Settings

import Codec.BMP
import Data.List
import qualified Data.ByteString as BS
import Data.WAVE
import qualified Data.Vector.Unboxed as V


type Color = BS.ByteString
type Duration = Double
type Time = Double


type V2 a = (a , a)

type V2D = V2 Double
type V2I = V2 Int

type SoundClosure = (Double -> Double) 
type Plotter = (Spire,SoundClosure)




data Spire = Spire Time Duration (SoundClosure -> Double -> V2D)

bgColor, lineColor :: Color

lineColor = BS.pack [   0,   0,   0,   0]
bgColor   = BS.pack [ 255, 255, 255,   0]


{-# INLINE vmap #-}
vmap :: (a -> b) -> V2 a -> V2 b
vmap fn = \ (a,b) -> (fn a,fn b)




{-# INLINE line #-}
line :: V2I -> V2I -> [V2I]
line l@(x1,y1) r@(x2,y2) | abs (x1 - x2) < abs (y1 - y2) = if y1 == y2 then [l,r] else map fn2 [min y1 y2 .. max y1 y2]
                         | otherwise = if x1 == x2 then [l,r] else map fn1 [min x1 x2 .. max x1 x2] 
    where
        fn1 = \ x -> (x , y1 + (y1 - y2) * (x1 - x) `div` (x2 -x1))
        fn2 = \ y -> (x1 + (x1 - x2) * (y1 - y) `div` (y2 -y1) , y)


-----------------------------------------------------------------------------------------------------------------------


makeSpire :: Time -> Double-> Duration -> Spire
makeSpire period ampl duration = Spire (period/2) duration $ \ a t -> let
    p = 1 - ampl - adp * t + ampl * (a t) 
    h = p2dp * t
    in vmap ((+ 1)  . (*p)) (sin h, cos h) 
    where
        p2dp = 2 * pi / period
        adp = 1.5 * ampl / period
    


bmpFromPoints :: Int -> [V2I] -> BMP
bmpFromPoints sz lst = packRGBA32ToBMP24 sz sz . BS.concat . fn (0,0) . map head . group . sort $ lst where
    fn (i,j) ((m,n):r) = lineColor : replicate fill bgColor ++ fn (m,n) r where 
        fill = (m-i-1)*sz + (sz-j-1 + n)
    fn (i,j) _ = lineColor : replicate fill bgColor where 
        fill = (sz-i-1)*sz + (sz-j-1)



calcPoints :: Int -> Plotter -> [V2I]
calcPoints sz' ((Spire tp dur fn),sound) = concat $ zipWith line bpoints (tail bpoints) where
    sz = fromIntegral sz'
    delta = tp / sz 
    npoints = [0.0,delta .. dur-delta]
    bpoints = map (vmap (floor . (/2) . (*sz)) . fn sound) npoints



printFigure :: String -> Int -> [V2I] -> IO ()
printFigure path sz = writeBMP path . bmpFromPoints sz



getWave :: String -> Spire -> IO (SoundClosure,Duration)
getWave path (Spire _ dur _) = do
    WAVE (WAVEHeader _ fr _ (Just fc)) samples <- getWAVEFile path
    let fr' = fromIntegral fr
    let samples' = V.fromListN fc $ map ( (\x -> signum x - x) . sampleToDouble . head) samples
    let closure = \t -> let n = floor $ t * fr' in 
            case t < dur && n < fc of
                True -> samples' V.! n
                _ -> 0.0
    return (closure, fromIntegral fc / fromIntegral fr)



buildPlotter :: Settings -> String -> IO (Spire,SoundClosure)
buildPlotter set path = do
    let Just [p,a,d] = sequence $ map (flip lookup set) [Period,Amplitude,Duration]
        spire@(Spire per dur fn) = makeSpire p a d 
    (sound,dur') <- getWave path spire
    return $ (Spire per (min dur dur') fn, sound)
