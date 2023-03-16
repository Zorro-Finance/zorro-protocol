#!/bin/zsh

echo "Starting Zorro test run..."

# Env 
export $(cat ./.env | xargs)

# Source
source ./forkchain.sh

# Start chains
## Mainnet forks
ganache_instance_avax=$(run_mainnet_fork "avax" $MAINNET_FORK_AVAX)
# ganache_instance_bnb=$(run_mainnet_fork "bnb" $MAINNET_FORK_BNB)

# Run migrations with reset flag
GANACHE_CLOUD_URL="http://0.0.0.0:$(ganache_port 'avax')" truffle migrate --network avaxfork #--reset
# GANACHE_CLOUD_URL="http://0.0.0.0:$(ganache_port 'bnb')" truffle migrate --network bnbfork #--reset

# Run test on each chain
GANACHE_CLOUD_URL="http://0.0.0.0:$(ganache_port 'avax')" truffle test test/vaults/VaultStandardAMM.js --network avaxfork --migrate-none
# GANACHE_CLOUD_URL="http://0.0.0.0:$(ganache_port 'bnb')" truffle test test/vaults/VaultZorro.js --network bnbfork --migrate-none

# Stop ganache
# ganache instances stop $ganache_instance_avax
# ganache instances stop $ganache_instance_bnb

echo "Finished test run!"