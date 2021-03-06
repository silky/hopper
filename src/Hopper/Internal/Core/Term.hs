{-# LANGUAGE DeriveDataTypeable #-}

module  Hopper.Internal.Core.Term where

import Hopper.Internal.Core.Literal
import Hopper.Internal.Type.BinderInfo (BinderInfo)
import Hopper.Utils.LocallyNameless

import Data.Data
import Data.Word (Word32)

import qualified Data.Vector as V

data Term =
  V  Variable
  | BinderLevelShiftUP Word32 Term  --
  | ELit !Literal
  | Return !(V.Vector Term)  -- explicit multiple return values
                      -- should V x be replaced by Return [x] ?
                      --  once we lower to ANF
                      -- NOTE: for valid expressions,
  | EnterThunk !(Term) -- because we're in a strict IR rep,
                        -- we dont need to provide a seq like operation
                          -- seq a b === let _ := enterThunk a in b

  | Delay !(Term )  --- Delay is a Noop on Thunked values, otherwise creates a Thunked
                    --- note: may need to change their semantics later?!
                    --- Q: is it valid to thunk a thunked value? (no?)
  | App !(Term  )  !(V.Vector Term  )   --this is not curried :)
  | PrimApp  !PrimOpId --
             !(V.Vector Term  ) -- not sure if this is needed, but lets go with it for now

  | Lam !(V.Vector BinderInfo)
        -- TODO: to properly translate to ANF, we need return arity info
        !Term
  | Let !(V.Vector BinderInfo)
        !Term --- RHS
        !Term --- BODY
  deriving ({-Show1,Read1,Ord1,Eq1,-}Ord,Eq,Show,Read{-,Functor,Foldable-},Typeable{-,Traversable-})


--- NOTE: USE STE MONAD ONCE WE MIGRATE TO HSUM DESIGN
--- this is kinda only for "inlining" on debruijin variables for now
substitute :: Word32 -> (BinderSlot  -> Maybe Term) -> Term -> Either (String,Word32) Term
substitute baseLevel initMapper initTerm = goSub 0 initMapper initTerm
  where
    goSub :: Word32 -> (BinderSlot  -> Maybe Term) -> Term -> Either (String,Word32) Term
    goSub shift mapper  var@(V (LocalVar (LocalNamelessVar lnLvl bslt@(BinderSlot slot))))
                |  lnLvl == (shift + baseLevel) =
                        maybe (Left ("bad slot", slot))
                              (Right . BinderLevelShiftUP shift )
                             $ mapper bslt
                | otherwise =  Right var
    goSub _l _m var@(V (GlobalVarSym _ )) = Right var
    goSub shift mapper (Return ls) =  fmap Return $  mapM (goSub shift mapper ) ls
    goSub shift mapper (App fun args) =
          do   funNew <- goSub shift mapper fun
               argsNew <-  mapM (goSub shift mapper) args
               Right (App funNew argsNew)
    goSub shift mapper (Lam binders bod) =
          do   bodNew <- goSub (shift +1 )  mapper bod ; Right (Lam binders bodNew)
    goSub shift mapper (Let binders rhs bod) =
          do  rhsNew <- goSub shift mapper rhs ;
              bodNew <- goSub (shift +1 ) mapper bod ;
              Right (Let binders rhsNew bodNew)
    goSub shift mapper (PrimApp primop args) =
          do  argsNew <- mapM (goSub shift mapper) args
              Right (PrimApp primop argsNew)
    goSub shift mapper (BinderLevelShiftUP posAmt bod)
      | posAmt <= baseLevel + shift  = -- TODO AUDIT THIS TO TILL IT SCREAMS
          do  bodNew <- substitute (baseLevel + shift - posAmt) mapper bod
              Right (BinderLevelShiftUP posAmt bodNew)
      | otherwise = Left ("weird level shift appeared, you've been eaten by a grue", posAmt )
                --- OR WHATTTTTT??!?!?!?!
    goSub _shift _mapper lit@(ELit _)  = Right lit
    goSub shift mapper (EnterThunk bod ) =  fmap EnterThunk $ goSub shift mapper bod
    goSub shift mapper (Delay bod ) = fmap Delay $ goSub shift mapper bod



{-
            _ _ (BinderLevelShiftUP _ _)
            _ _ (ELit _)
            _ _ (EnterThunk _)
            _ _ (Delay _)

-}
