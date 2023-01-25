#!/bin/zsh

echo "Starting Zorro test run..."

# Get chain

# Mainnet fork instantiation
run_mainnet_fork () {
    chainId=0
    ganachePort=8545

    case $1 in 
        "avax")
            chainId=43115
            ganachePort=8545
        ;;
        "bnb")
            chainId=57
            ganachePort=8546
        ;;
    esac

    # echo "chain ID is $chainId"

    ganache \
        --server.host=0.0.0.0 \
        --chain.chainId=$chainId \
        --chain.networkId=$chainId \
        --wallet.defaultBalance=1000000 \
        --fork=$2 \
        --server.port=$ganachePort \
        --detach
}

# Test AVAX chain on-chain tests

# Start chains
## Mainnet forks
ganache_instance_avax=$(run_mainnet_fork "avax" $MAINNET_FORK_AVAX)
ganache_instance_bnb=$(run_mainnet_fork "bnb" $MAINNET_FORK_BNB)

# Run migrations with reset flag
truffle migrate --network avaxfork --reset
truffle migrate --network bnbfork --reset

# Run test on each chain
truffle test --network avaxfork --compile-none --stacktrace-extra
truffle test --network bnbfork --compile-none --stacktrace-extra

# Stop ganache
ganache instances stop $ganache_instance_avax
ganache instances stop $ganache_instance_bnb

echo "Finished test run!"