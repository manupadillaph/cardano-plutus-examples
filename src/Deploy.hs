{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE AllowAmbiguousTypes        #-}
{-# LANGUAGE NumericUnderscores         #-}

module Deploy where

--Import Externos

import qualified Cardano.Api                         as CardanoApi 
import qualified Cardano.Api.Shelley                 as ApiShelley (PlutusScript (..), PlutusScriptV1)
import qualified Codec.Serialise                     as CodecSerialise (serialise)
import qualified Data.Aeson                          as DataAeson (encode) --,ToJSON, FromJSON
import qualified Data.ByteString.Lazy                as LBS
import qualified Data.ByteString.Short               as SBS
import qualified Data.String                         as DataString (IsString(fromString))
--import qualified Data.Map                            as DataMap
import qualified Ledger                              (PaymentPubKeyHash(..))
import qualified Plutus.V1.Ledger.Api                as LedgerApiV1
import qualified Plutus.V1.Ledger.Scripts            as LedgerScriptsV1
import qualified PlutusTx
import           PlutusTx.Prelude                    hiding (unless)
import qualified System.Directory                    as SystemDirectory          
import qualified System.FilePath.Posix               as SystemFilePathPosix            
import qualified Prelude                             as P

--Import Internos

import qualified Validators.LockerV1
import qualified Validators.AlwaysTrueV1
import qualified Validators.AlwaysFalseV1
import qualified Validators.BeneficiaryV1
import qualified Validators.DeadlineV1
import qualified Validators.RedeemerV1
import qualified Validators.MarketNFTV1

import qualified Validators.StakePlusV1
import qualified Validators.StakeSimpleV1

import qualified MintingPolicies.FreeV1              (policy)
import qualified MintingPolicies.NFTV1               (policy)
import qualified MintingPolicies.NFTSignedV1         (policy)
import qualified MintingPolicies.SignedV1            (policy)
import qualified MintingPolicies.TokensV1            (policy)
import qualified MintingPolicies.TokensSignedV1      (policy)

import qualified Utils                               (unsafeReadTxOutRef, unsafeReadAddress, unsafePaymentPubKeyHash, pkhFromStr)

--Modulo:

dataToScriptData :: PlutusTx.Data -> CardanoApi.ScriptData
dataToScriptData (PlutusTx.Constr n xs) = CardanoApi.ScriptDataConstructor n $ dataToScriptData <$> xs
dataToScriptData (PlutusTx.Map xs)      = CardanoApi.ScriptDataMap [(dataToScriptData x, dataToScriptData y) | (x, y) <- xs]
dataToScriptData (PlutusTx.List xs)     = CardanoApi.ScriptDataList $ dataToScriptData <$> xs
dataToScriptData (PlutusTx.I n)         = CardanoApi.ScriptDataNumber n
dataToScriptData (PlutusTx.B bs)        = CardanoApi.ScriptDataBytes bs

writeJSON :: PlutusTx.ToData a => P.FilePath -> a -> P.IO ()
writeJSON file = LBS.writeFile file . DataAeson.encode . CardanoApi.scriptDataToJson CardanoApi.ScriptDataJsonDetailedSchema . dataToScriptData . PlutusTx.toData

writeUnit :: P.String -> P.IO ()
writeUnit path = writeJSON (path ++ "/unit.json") ()

--Writing Validators to disk

getScriptUnValidatorV1 :: LedgerScriptsV1.Validator -> LedgerScriptsV1.Script
getScriptUnValidatorV1  = LedgerScriptsV1.unValidatorScript 

getScriptShortBsV1 :: LedgerScriptsV1.Script -> SBS.ShortByteString
getScriptShortBsV1 = SBS.toShort . LBS.toStrict . CodecSerialise.serialise 

getScriptSerialisedV1 :: SBS.ShortByteString -> ApiShelley.PlutusScript ApiShelley.PlutusScriptV1
getScriptSerialisedV1 = ApiShelley.PlutusScriptSerialised 

writeValidatorV1 :: P.String -> P.String -> LedgerScriptsV1.Validator -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeValidatorV1 path file codeValidator =  do
    let 
        --v1dir = "V1"
        scriptUnValidatorV1 = getScriptUnValidatorV1 codeValidator
        scriptShortBsV1 = getScriptShortBsV1 scriptUnValidatorV1
        scriptSerialisedV1 = getScriptSerialisedV1 scriptShortBsV1           
    SystemDirectory.createDirectoryIfMissing True path --SystemFilePathPosix.</> v1dir
    CardanoApi.writeFileTextEnvelope (path SystemFilePathPosix.</> file) Nothing scriptSerialisedV1

getScriptMintingPolicyV1 :: LedgerScriptsV1.MintingPolicy -> LedgerScriptsV1.Script
getScriptMintingPolicyV1  = LedgerScriptsV1.getMintingPolicy

writeMintingPolicyV1 :: P.String -> P.String -> LedgerScriptsV1.MintingPolicy -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeMintingPolicyV1 path file policy =  do
    let 
        --v1dir = "V1"
        scriptMintingPolicyV1 = getScriptMintingPolicyV1 policy
        scriptShortBsV1 = getScriptShortBsV1 scriptMintingPolicyV1
        scriptSerialisedV1 = getScriptSerialisedV1 scriptShortBsV1           
    SystemDirectory.createDirectoryIfMissing True path --SystemFilePathPosix.</> v1dir
    CardanoApi.writeFileTextEnvelope (path SystemFilePathPosix.</> file) Nothing scriptSerialisedV1

---------------------------

writeValidatorLockerV1 :: P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeValidatorLockerV1 path file = do
    writeValidatorV1 path (file ++ ".plutus") Validators.LockerV1.codeValidator  

writeValidatorLockerV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorLockerV1Hash path file = do
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") Validators.LockerV1.hashValidator

-- -- writeValidatorLockerAddress :: P.String -> P.String -> P.IO ()
-- -- writeValidatorLockerAddress path file = do
-- --     writeJSON  (path SystemFilePathPosix.</> file ++ ".addr") (Validators.LockerV1.addressValidator)

writeValidatorLockerV1Redeemer :: P.String -> P.String -> Integer -> P.IO ()
writeValidatorLockerV1Redeemer path file opcion = do
    let 
        redeemer = Validators.LockerV1.ValidatorRedeemer { 
            Validators.LockerV1.rTipo = opcion
        }
        opcionStr = P.show opcion
    writeJSON (path SystemFilePathPosix.</> file ++ ".json") redeemer

writeValidatorLockerV1Datum:: P.String -> P.String -> P.String -> Integer -> Integer -> Integer-> P.IO ()
writeValidatorLockerV1Datum path file creator deadline name qty = do
    let 
        pkh = Utils.pkhFromStr creator
    
        datum = Validators.LockerV1.ValidatorDatum {
            Validators.LockerV1.dData = Validators.LockerV1.ValidatorData{
                    Validators.LockerV1.aCreator =  Ledger.PaymentPubKeyHash pkh,
                    Validators.LockerV1.aDeadline    = P.fromInteger  deadline,
                    Validators.LockerV1.aName = name,
                    Validators.LockerV1.aAdaQty  = qty 
                }
            }

    writeJSON (path SystemFilePathPosix.</> file ++ ".json") datum

---------------------------

writeValidatorAlwaysFalseV1 :: P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeValidatorAlwaysFalseV1 path file = do
    writeValidatorV1 path (file ++ ".plutus") Validators.AlwaysFalseV1.codeValidator  

writeValidatorAlwaysFalseV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorAlwaysFalseV1Hash path file = do
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") Validators.AlwaysFalseV1.hashValidator

---------------------------

writeValidatorAlwaysTrueV1 :: P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeValidatorAlwaysTrueV1 path file = do
    writeValidatorV1 path (file ++ ".plutus") Validators.AlwaysTrueV1.codeValidator  

---------------------------

writeValidatorAlwaysTrueV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorAlwaysTrueV1Hash path file = do
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") Validators.AlwaysTrueV1.hashValidator

---------------------------

writeValidatorBeneficiaryV1 :: P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeValidatorBeneficiaryV1 path file = do
    writeValidatorV1 path (file ++ ".plutus") Validators.BeneficiaryV1.codeValidator  

writeValidatorBeneficiaryV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorBeneficiaryV1Hash path file = do
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") Validators.BeneficiaryV1.hashValidator

---------------------------

writeValidatorDeadlineV1 :: P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeValidatorDeadlineV1 path file = do
    writeValidatorV1 path (file ++ ".plutus") Validators.DeadlineV1.codeValidator  

writeValidatorDeadlineV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorDeadlineV1Hash path file = do
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") Validators.DeadlineV1.hashValidator

---------------------------

writeValidatorRedeemerV1 :: P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeValidatorRedeemerV1 path file = do
    writeValidatorV1 path (file ++ ".plutus") Validators.RedeemerV1.codeValidator  

writeValidatorRedeemerV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorRedeemerV1Hash path file = do
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") Validators.RedeemerV1.hashValidator

---------------------------

writeValidatorMarketNFTV1 :: P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeValidatorMarketNFTV1 path file = do
    writeValidatorV1 path (file ++ ".plutus") Validators.MarketNFTV1.codeValidator  

writeValidatorMarketNFTV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorMarketNFTV1Hash path file = do
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") Validators.MarketNFTV1.hashValidator

writeValidatorMarketNFTV1Redeemer :: P.String -> P.String -> Integer -> P.IO ()
writeValidatorMarketNFTV1Redeemer path file opcion = do
    return ()
    -- let 
    --     redeemer = Validators.MarketNFTV1.ValidatorRedeemer { 
    --         Validators.MarketNFTV1.rTipo = opcion
    --     }
    --     opcionStr = P.show opcion
    -- writeJSON (path SystemFilePathPosix.</> file ++ ".json") redeemer

writeValidatorMarketNFTV1Datum:: P.String -> P.String -> P.String -> Integer -> Integer -> Integer-> P.IO ()
writeValidatorMarketNFTV1Datum path file creator deadline name qty = do
    return ()
    -- let 
    --     pkh = Utils.pkhFromStr creator
    
    --     datum = Validators.MarketNFTV1.ValidatorDatum {
    --         Validators.MarketNFTV1.dData = Validators.MarketNFTV1.ValidatorData{
    --                 Validators.MarketNFTV1.aCreator =  Ledger.PaymentPubKeyHash pkh,
    --                 Validators.MarketNFTV1.aDeadline    = P.fromInteger  deadline,
    --                 Validators.MarketNFTV1.aName = name,
    --                 Validators.MarketNFTV1.aAdaQty  = qty 
    --             }
    --         }

    -- writeJSON (path SystemFilePathPosix.</> file ++ ".json") datum

---------------------------

writeValidatorStakeSimpleV1 :: P.String -> P.String -> P.IO (Either (CardanoApi.FileError ()) ())
writeValidatorStakeSimpleV1 path file = do
    --return $ Right ()
    --TODO: falta crear pParams :: PoolParams que va como parametro
    let
        pParams = Validators.StakeSimpleV1.examplePoolParams
            
    writeValidatorV1 path (file ++ ".plutus") $ Validators.StakeSimpleV1.codeValidator pParams

writeValidatorStakeSimpleV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorStakeSimpleV1Hash path file = do
    --return ()
    --TODO: falta crear pParams :: PoolParams que va como parametro
    let
        pParams = Validators.StakeSimpleV1.examplePoolParams
            
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") $  Validators.StakeSimpleV1.hashValidator pParams

-- -- writeValidatorStakeSimpleV1Address :: P.String -> P.String -> P.IO ()
-- -- writeValidatorStakeSimpleV1Address path file = do
-- --     writeJSON  (path SystemFilePathPosix.</> file ++ ".addr") (Validators.StakeSimpleV1.addressValidator)

writeValidatorStakeSimpleV1Redeemer :: P.String -> P.String -> Integer -> P.IO ()
writeValidatorStakeSimpleV1Redeemer path file opcion = do
    return ()
    -- let 
    --     redeemer = Validators.StakeSimpleV1.ValidatorRedeemer { 
    --         Validators.StakeSimpleV1.rTipo = opcion
    --     }
    --     opcionStr = P.show opcion
    -- writeJSON (path SystemFilePathPosix.</> file ++ ".json") redeemer

writeValidatorStakeSimpleV1Datum:: P.String -> P.String -> P.String -> Integer -> Integer -> Integer-> P.IO ()
writeValidatorStakeSimpleV1Datum path file creator deadline name qty = do
    return ()
    -- let 
    --     pkh = Utils.pkhFromStr creator
    
    --     datum = Validators.StakePlusV1.ValidatorDatum {
    --         Validators.StakePlusV1.dData = Validators.StakePlusV1.ValidatorData{
    --                 Validators.StakePlusV1.aCreator =  Ledger.PaymentPubKeyHash pkh,
    --                 Validators.StakePlusV1.aDeadline    = fromInteger  deadline,
    --                 Validators.StakePlusV1.aName = name,
    --                 Validators.StakePlusV1.aAdaQty  = qty 
    --             }
    --         }

    -- writeJSON (path SystemFilePathPosix.</> file ++ ".json") datum
---------------------------

writeValidatorStakePlusV1 :: P.String -> P.String -> P.IO (Either (CardanoApi.FileError ()) ())
writeValidatorStakePlusV1 path file = do
    --return $ Right ()
    --TODO: falta crear pParams :: PoolParams que va como parametro
    let
        pParams = Validators.StakePlusV1.examplePoolParams
            
    writeValidatorV1 path (file ++ ".plutus") $ Validators.StakePlusV1.codeValidator pParams

writeValidatorStakePlusV1Hash :: P.String -> P.String -> P.IO ()
writeValidatorStakePlusV1Hash path file = do
    --return ()
    --TODO: falta crear pParams :: PoolParams que va como parametro
    let
        pParams = Validators.StakePlusV1.examplePoolParams
            
    writeJSON (path SystemFilePathPosix.</> file ++ ".hash") $  Validators.StakePlusV1.hashValidator pParams

-- -- writeValidatorStakePlusV1Address :: P.String -> P.String -> P.IO ()
-- -- writeValidatorStakePlusV1Address path file = do
-- --     writeJSON  (path SystemFilePathPosix.</> file ++ ".addr") (Validators.StakePlusV1.addressValidator)

writeValidatorStakePlusV1Redeemer :: P.String -> P.String -> P.String -> Integer -> P.IO ()
writeValidatorStakePlusV1Redeemer path file master' fund = do

    let 
        master = Ledger.PaymentPubKeyHash $ Utils.pkhFromStr master'
        pParams = Validators.StakePlusV1.examplePoolParams
        redeemer = LedgerApiV1.Redeemer $ PlutusTx.toBuiltinData (Validators.StakePlusV1.mkRedeemMasterFundPool (Validators.StakePlusV1.ppPoolNFT pParams) master fund Validators.StakePlusV1.exampleTxOutRef)

    writeJSON (path SystemFilePathPosix.</> file ++ ".json") redeemer

writeValidatorStakePlusV1Datum:: P.String -> P.String -> P.String -> Integer -> P.IO ()
writeValidatorStakePlusV1Datum path file master' fund = do
    let 
        pParams = Validators.StakePlusV1.examplePoolParams
        master = Ledger.PaymentPubKeyHash $ Utils.pkhFromStr master'
        masterFundersNew = Validators.StakePlusV1.mkMasterFunder master fund
        masterFunders = [masterFundersNew]
        userNFTs = []
        cashedOut = 0
        countPoolState = 1
        datum = Validators.StakePlusV1.mkPoolState (Validators.StakePlusV1.ppPoolNFT pParams) masterFunders userNFTs cashedOut countPoolState

    writeJSON (path SystemFilePathPosix.</> file ++ ".json") datum

---------------------------

--Writing Minting Policies to disk

writeMintingPolicyFreeV1 :: P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeMintingPolicyFreeV1 path file  = do
    let p    = MintingPolicies.FreeV1.policy
    writeMintingPolicyV1 path (file ++ ".plutus") p 

writeMintingPolicyNFTV1 :: P.String -> P.String ->  P.String ->  P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeMintingPolicyNFTV1 path file oref' tn' = do
    let oref = Utils.unsafeReadTxOutRef oref'
        tn   = DataString.fromString tn'
        p    = MintingPolicies.NFTV1.policy oref tn
    writeMintingPolicyV1 path (file ++ ".plutus") p 

writeMintingPolicyNFTSignedV1 :: P.String -> P.String -> P.String ->  P.String ->  P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeMintingPolicyNFTSignedV1 path file addr' oref' tn' = do
    let pkh  = Utils.unsafePaymentPubKeyHash $ Utils.unsafeReadAddress addr'
        oref = Utils.unsafeReadTxOutRef oref'
        tn   = DataString.fromString tn'
        p    = MintingPolicies.NFTSignedV1.policy pkh oref tn
    writeMintingPolicyV1 path (file ++ ".plutus") p 

writeMintingPolicySignedV1Addr ::  P.String -> P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeMintingPolicySignedV1Addr path file addr' = do
    let pkh  = Utils.unsafePaymentPubKeyHash $ Utils.unsafeReadAddress addr'
        p    = MintingPolicies.SignedV1.policy pkh
    writeMintingPolicyV1 path (file ++ ".plutus") p 

writeMintingPolicySignedV1Pkh ::  P.String -> P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeMintingPolicySignedV1Pkh path file pkh' = do
    let pkh  =  Ledger.PaymentPubKeyHash $ Utils.pkhFromStr pkh'
        p    = MintingPolicies.SignedV1.policy pkh
    writeMintingPolicyV1 path (file ++ ".plutus") p 

writeMintingPolicyTokensV1 :: P.String -> P.String -> P.String -> P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeMintingPolicyTokensV1 path file oref' tn' amt' = do
    let oref = Utils.unsafeReadTxOutRef oref'
        tn   = DataString.fromString tn'
        amt  = P.read amt'
        p    = MintingPolicies.TokensV1.policy oref tn amt
    writeMintingPolicyV1 path (file ++ ".plutus") p 

writeMintingPolicyTokensSignedV1 :: P.String -> P.String -> P.String -> P.String -> P.String -> P.String -> P.IO (P.Either (CardanoApi.FileError ()) ())
writeMintingPolicyTokensSignedV1 path file addr' oref' tn' amt' = do
    let pkh  = Utils.unsafePaymentPubKeyHash $ Utils.unsafeReadAddress addr'
        oref = Utils.unsafeReadTxOutRef oref'
        tn   = DataString.fromString tn'
        amt  = P.read amt'
        p    = MintingPolicies.TokensSignedV1.policy pkh oref tn amt
    writeMintingPolicyV1 path (file ++ ".plutus") p 

