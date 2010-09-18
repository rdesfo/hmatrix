{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE UndecidableInstances #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Numeric.Container
-- Copyright   :  (c) Alberto Ruiz 2010
-- License     :  GPL-style
--
-- Maintainer  :  Alberto Ruiz <aruiz@um.es>
-- Stability   :  provisional
-- Portability :  portable
--
-- Numeric classes for containers of numbers, including conversion routines
--
-----------------------------------------------------------------------------

module Numeric.Container (
    Container(..),
    Product(..),
    mXm,mXv,vXm,
    outer, kronecker,

    Convert(..),
    Complexable(),
    RealElement(),

    RealOf, ComplexOf, SingleOf, DoubleOf,

    IndexOf,
    module Data.Complex
) where

import Data.Packed
import Numeric.Conversion
import Data.Packed.Internal
import Numeric.GSL.Vector

import Data.Complex
import Control.Monad(ap)

import Numeric.LinearAlgebra.LAPACK(multiplyR,multiplyC,multiplyF,multiplyQ)

-------------------------------------------------------------------

type family IndexOf c

type instance IndexOf Vector = Int
type instance IndexOf Matrix = (Int,Int)

-------------------------------------------------------------------

-- | Basic element-by-element functions for numeric containers
class (Complexable c, Element e) => Container c e where
    -- | create a structure with a single element
    scalar      :: e -> c e
    -- | complex conjugate
    conj        :: c e -> c e
    scale       :: e -> c e -> c e
    -- | scale the element by element reciprocal of the object:
    --
    -- @scaleRecip 2 (fromList [5,i]) == 2 |> [0.4 :+ 0.0,0.0 :+ (-2.0)]@
    scaleRecip  :: e -> c e -> c e
    addConstant :: e -> c e -> c e
    add         :: c e -> c e -> c e
    sub         :: c e -> c e -> c e
    -- | element by element multiplication
    mul         :: c e -> c e -> c e
    -- | element by element division
    divide      :: c e -> c e -> c e
    equal       :: c e -> c e -> Bool
    --
    -- | cannot implement instance Functor because of Element class constraint
    cmap        :: (Element a, Element b) => (a -> b) -> c a -> c b
    -- | constant structure of given size
    konst       :: e -> IndexOf c -> c e
    --
    -- | indexing function
    atIndex     :: c e -> IndexOf c -> e
    -- | index of min element
    minIndex    :: c e -> IndexOf c
    -- | index of max element
    maxIndex    :: c e -> IndexOf c
    -- | value of min element
    minElement  :: c e -> e
    -- | value of max element
    maxElement  :: c e -> e
    -- the C functions sumX/prodX are twice as fast as using foldVector
    -- | the sum of elements (faster than using @fold@)
    sumElements :: c e -> e
    -- | the product of elements (faster than using @fold@)
    prodElements :: c e -> e

-- -- | Basic element-by-element functions.
-- class (Element e, Container c e) => Linear c e where


--------------------------------------------------------------------------

instance Container Vector Float where
    scale = vectorMapValF Scale
    scaleRecip = vectorMapValF Recip
    addConstant = vectorMapValF AddConstant
    add = vectorZipF Add
    sub = vectorZipF Sub
    mul = vectorZipF Mul
    divide = vectorZipF Div
    equal u v = dim u == dim v && maxElement (vectorMapF Abs (sub u v)) == 0.0
    scalar x = fromList [x]
    konst = constantD
    conj = conjugateD
    cmap = mapVector
    atIndex = (@>)
    minIndex     = round . toScalarF MinIdx
    maxIndex     = round . toScalarF MaxIdx
    minElement  = toScalarF Min
    maxElement  = toScalarF Max
    sumElements  = sumF
    prodElements = prodF

instance Container Vector Double where
    scale = vectorMapValR Scale
    scaleRecip = vectorMapValR Recip
    addConstant = vectorMapValR AddConstant
    add = vectorZipR Add
    sub = vectorZipR Sub
    mul = vectorZipR Mul
    divide = vectorZipR Div
    equal u v = dim u == dim v && maxElement (vectorMapR Abs (sub u v)) == 0.0
    scalar x = fromList [x]
    konst = constantD
    conj = conjugateD
    cmap = mapVector
    atIndex = (@>)
    minIndex     = round . toScalarR MinIdx
    maxIndex     = round . toScalarR MaxIdx
    minElement  = toScalarR Min
    maxElement  = toScalarR Max
    sumElements  = sumR
    prodElements = prodR

instance Container Vector (Complex Double) where
    scale = vectorMapValC Scale
    scaleRecip = vectorMapValC Recip
    addConstant = vectorMapValC AddConstant
    add = vectorZipC Add
    sub = vectorZipC Sub
    mul = vectorZipC Mul
    divide = vectorZipC Div
    equal u v = dim u == dim v && maxElement (mapVector magnitude (sub u v)) == 0.0
    scalar x = fromList [x]
    konst = constantD
    conj = conjugateD
    cmap = mapVector
    atIndex = (@>)
    minIndex     = minIndex . fst . fromComplex . (zipVectorWith (*) `ap` mapVector conjugate)
    maxIndex     = maxIndex . fst . fromComplex . (zipVectorWith (*) `ap` mapVector conjugate)
    minElement  = ap (@>) minIndex
    maxElement  = ap (@>) maxIndex
    sumElements  = sumC
    prodElements = prodC

instance Container Vector (Complex Float) where
    scale = vectorMapValQ Scale
    scaleRecip = vectorMapValQ Recip
    addConstant = vectorMapValQ AddConstant
    add = vectorZipQ Add
    sub = vectorZipQ Sub
    mul = vectorZipQ Mul
    divide = vectorZipQ Div
    equal u v = dim u == dim v && maxElement (mapVector magnitude (sub u v)) == 0.0
    scalar x = fromList [x]
    konst = constantD
    conj = conjugateD
    cmap = mapVector
    atIndex = (@>)
    minIndex     = minIndex . fst . fromComplex . (zipVectorWith (*) `ap` mapVector conjugate)
    maxIndex     = maxIndex . fst . fromComplex . (zipVectorWith (*) `ap` mapVector conjugate)
    minElement  = ap (@>) minIndex
    maxElement  = ap (@>) maxIndex
    sumElements  = sumQ
    prodElements = prodQ

---------------------------------------------------------------

instance (Container Vector a) => Container Matrix a where
    scale x = liftMatrix (scale x)
    scaleRecip x = liftMatrix (scaleRecip x)
    addConstant x = liftMatrix (addConstant x)
    add = liftMatrix2 add
    sub = liftMatrix2 sub
    mul = liftMatrix2 mul
    divide = liftMatrix2 divide
    equal a b = cols a == cols b && flatten a `equal` flatten b
    scalar x = (1><1) [x]
    konst v (r,c) = reshape c (konst v (r*c))
    conj = liftMatrix conjugateD
    cmap f = liftMatrix (mapVector f)
    atIndex = (@@>)
    minIndex m = let (r,c) = (rows m,cols m)
                     i = (minIndex $ flatten m)
                 in (i `div` c,i `mod` c)
    maxIndex m = let (r,c) = (rows m,cols m)
                     i = (maxIndex $ flatten m)
                 in (i `div` c,i `mod` c)
    minElement = ap (@@>) minIndex
    maxElement = ap (@@>) maxIndex
    sumElements = sumElements . flatten
    prodElements = prodElements . flatten

----------------------------------------------------


-- | Matrix product and related functions
class Element e => Product e where
    -- | matrix product
    multiply :: Matrix e -> Matrix e -> Matrix e
    -- | dot (inner) product
    dot        :: Vector e -> Vector e -> e
    -- | sum of absolute value of elements (differs in complex case from @norm1@)
    absSum     :: Vector e -> RealOf e
    -- | sum of absolute value of elements
    norm1      :: Vector e -> RealOf e
    -- | euclidean norm
    norm2      :: Vector e -> RealOf e
    -- | element of maximum magnitude
    normInf    :: Vector e -> RealOf e

instance Product Float where
    norm2      = toScalarF Norm2
    absSum     = toScalarF AbsSum
    dot        = dotF
    norm1      = toScalarF AbsSum
    normInf    = maxElement . vectorMapF Abs
    multiply = multiplyF

instance Product Double where
    norm2      = toScalarR Norm2
    absSum     = toScalarR AbsSum
    dot        = dotR
    norm1      = toScalarR AbsSum
    normInf    = maxElement . vectorMapR Abs
    multiply = multiplyR

instance Product (Complex Float) where
    norm2      = toScalarQ Norm2
    absSum     = toScalarQ AbsSum
    dot        = dotQ
    norm1      = sumElements . fst . fromComplex . vectorMapQ Abs
    normInf    = maxElement . fst . fromComplex . vectorMapQ Abs
    multiply = multiplyQ

instance Product (Complex Double) where
    norm2      = toScalarC Norm2
    absSum     = toScalarC AbsSum
    dot        = dotC
    norm1      = sumElements . fst . fromComplex . vectorMapC Abs
    normInf    = maxElement . fst . fromComplex . vectorMapC Abs
    multiply = multiplyC

----------------------------------------------------------

-- synonym for matrix product
mXm :: Product t => Matrix t -> Matrix t -> Matrix t
mXm = multiply

-- matrix - vector product
mXv :: Product t => Matrix t -> Vector t -> Vector t
mXv m v = flatten $ m `mXm` (asColumn v)

-- vector - matrix product
vXm :: Product t => Vector t -> Matrix t -> Vector t
vXm v m = flatten $ (asRow v) `mXm` m

{- | Outer product of two vectors.

@\> 'fromList' [1,2,3] \`outer\` 'fromList' [5,2,3]
(3><3)
 [  5.0, 2.0, 3.0
 , 10.0, 4.0, 6.0
 , 15.0, 6.0, 9.0 ]@
-}
outer :: (Product t) => Vector t -> Vector t -> Matrix t
outer u v = asColumn u `multiply` asRow v

{- | Kronecker product of two matrices.

@m1=(2><3)
 [ 1.0,  2.0, 0.0
 , 0.0, -1.0, 3.0 ]
m2=(4><3)
 [  1.0,  2.0,  3.0
 ,  4.0,  5.0,  6.0
 ,  7.0,  8.0,  9.0
 , 10.0, 11.0, 12.0 ]@

@\> kronecker m1 m2
(8><9)
 [  1.0,  2.0,  3.0,   2.0,   4.0,   6.0,  0.0,  0.0,  0.0
 ,  4.0,  5.0,  6.0,   8.0,  10.0,  12.0,  0.0,  0.0,  0.0
 ,  7.0,  8.0,  9.0,  14.0,  16.0,  18.0,  0.0,  0.0,  0.0
 , 10.0, 11.0, 12.0,  20.0,  22.0,  24.0,  0.0,  0.0,  0.0
 ,  0.0,  0.0,  0.0,  -1.0,  -2.0,  -3.0,  3.0,  6.0,  9.0
 ,  0.0,  0.0,  0.0,  -4.0,  -5.0,  -6.0, 12.0, 15.0, 18.0
 ,  0.0,  0.0,  0.0,  -7.0,  -8.0,  -9.0, 21.0, 24.0, 27.0
 ,  0.0,  0.0,  0.0, -10.0, -11.0, -12.0, 30.0, 33.0, 36.0 ]@
-}
kronecker :: (Product t) => Matrix t -> Matrix t -> Matrix t
kronecker a b = fromBlocks
              . splitEvery (cols a)
              . map (reshape (cols b))
              . toRows
              $ flatten a `outer` flatten b

-------------------------------------------------------------------


class Convert t where
    real    :: Container c t => c (RealOf t) -> c t
    complex :: Container c t => c t -> c (ComplexOf t)
    single  :: Container c t => c t -> c (SingleOf t)
    double  :: Container c t => c t -> c (DoubleOf t)
    toComplex   :: (Container c t, RealElement t) => (c t, c t) -> c (Complex t)
    fromComplex :: (Container c t, RealElement t) => c (Complex t) -> (c t, c t)


instance Convert Double where
    real = id
    complex = comp'
    single = single'
    double = id
    toComplex = toComplex'
    fromComplex = fromComplex'

instance Convert Float where
    real = id
    complex = comp'
    single = id
    double = double'
    toComplex = toComplex'
    fromComplex = fromComplex'

instance Convert (Complex Double) where
    real = comp'
    complex = id
    single = single'
    double = id
    toComplex = toComplex'
    fromComplex = fromComplex'

instance Convert (Complex Float) where
    real = comp'
    complex = id
    single = id
    double = double'
    toComplex = toComplex'
    fromComplex = fromComplex'

-------------------------------------------------------------------

type family RealOf x

type instance RealOf Double = Double
type instance RealOf (Complex Double) = Double

type instance RealOf Float = Float
type instance RealOf (Complex Float) = Float

type family ComplexOf x

type instance ComplexOf Double = Complex Double
type instance ComplexOf (Complex Double) = Complex Double

type instance ComplexOf Float = Complex Float
type instance ComplexOf (Complex Float) = Complex Float

type family SingleOf x

type instance SingleOf Double = Float
type instance SingleOf Float  = Float

type instance SingleOf (Complex a) = Complex (SingleOf a)

type family DoubleOf x

type instance DoubleOf Double = Double
type instance DoubleOf Float  = Double

type instance DoubleOf (Complex a) = Complex (DoubleOf a)

type family ElementOf c

type instance ElementOf (Vector a) = a
type instance ElementOf (Matrix a) = a
