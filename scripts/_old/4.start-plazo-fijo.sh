#!/bin/sh

echo "Nombre Wallet:"
read walletName

echo "Cantidad ADA:"
read cantidad

walletAddr=$(cat $SCRIPTS_FILES/${walletName}.addr)

walletTxIn=$(cat $SCRIPTS_FILES/${walletName}.utxo)

#scriptName="plazo-fijo"
echo "Nombre Script File:"
read scriptName

scriptAddr=$(cat $SCRIPTS_FILES/${scriptName}.addr)

$CARDANO_NODE/cardano-cli transaction build \
    --alonzo-era \
    --testnet-magic 1097911063 \
    --change-address $walletAddr \
    --tx-in $walletTxIn \
    --tx-out "$scriptAddr $cantidad lovelace" \
    --tx-out-datum-hash-file $SCRIPTS_FILES/datum-DEF2.json \
    --out-file $SCRIPTS_FILES/tx-${scriptName}.body

#--tx-out-datum-hash 690641c845d1bdd7217f1313e98f5b276088ae2a70b0f2b813217081daa3b291 \
    

$CARDANO_NODE/cardano-cli transaction sign \
    --tx-body-file $SCRIPTS_FILES/tx-${scriptName}.body \
    --signing-key-file $SCRIPTS_FILES/${walletName}.skey \
    --testnet-magic 1097911063 \
    --out-file $SCRIPTS_FILES/tx-${scriptName}.signed

$CARDANO_NODE/cardano-cli transaction submit \
    --testnet-magic 1097911063 \
    --tx-file $SCRIPTS_FILES/tx-${scriptName}.signed
