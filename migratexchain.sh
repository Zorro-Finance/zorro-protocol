#!/bin/zsh


echo "Starting testnet migrations for cross chain tests..."

# NOTE: IMPORTANT: Assumes code is already compiled (Run `truffle compile --all`)

# Load private key (mnemonic)
mnemonic=$(cat ./.testmnemonic)

# Migrate on avax public testnet
MNEMONIC_TEST=$mnemonic truffle migrate --network avaxtest --compile-none 
#--reset

# Migrate on bnb public testnet
MNEMONIC_TEST=$mnemonic truffle migrate --network bnbtest --compile-none 
#--reset

echo "Finished migrations for testnet!"

###
# To run xchain tests: Open a truffle console and run the commands in ./helpers/xchain.js
###