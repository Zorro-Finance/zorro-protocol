#!/bin/zsh

echo "Starting Zorro test run..."

# Env 
export $(cat ./.env | xargs)

# Source
source ./forkchain.sh

# Test AVAX chain on-chain tests

# Start chains
## Mainnet forks
# ganache_instance_avax=$(run_mainnet_fork "avax" $MAINNET_FORK_AVAX)
ganache_instance_bnb=$(run_mainnet_fork "bnb" $MAINNET_FORK_BNB)

# Run migrations with reset flag
# truffle migrate --network avaxfork #--reset
GANACHE_CLOUD_URL="http://0.0.0.0:$(ganache_port 'bnb')" truffle migrate --network bnbfork #--reset

# Run test on each chain
# truffle test --network avaxfork --compile-none --stacktrace-extra
# truffle test --network bnbfork --compile-none --stacktrace-extra

# Stop ganache
# ganache instances stop $ganache_instance_avax
ganache instances stop $ganache_instance_bnb

echo "Finished test run!"