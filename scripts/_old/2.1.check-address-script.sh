#!/bin/sh

#scriptName="plazo-fijo"
echo "Nombre Script File:"
read scriptName

scriptAddr=$(cat files/${scriptName}.addr)

echo $scriptAddr

$CARDANO_NODE/cardano-cli query utxo\
	 --address $scriptAddr --testnet-magic 1097911063 

