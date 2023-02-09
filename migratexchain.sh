#!/bin/zsh

# Set up cross chain tests

# Migrate on avax public testnet
truffle migrate --network avaxtest #--reset

# Migrate on bnb public testnet
truffle migrate --network bnbtest #--reset

###
# To run xchain tests: Open a truffle console and run the commands in ./helpers/xchain.js
###