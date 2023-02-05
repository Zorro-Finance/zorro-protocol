#!/bin/zsh

# Ganache port
ganache_port () {
    ganachePort=8545

    case $1 in 
        "avax")
            ganachePort=8545
        ;;
        "bnb")
            ganachePort=8546
        ;;
    esac

    echo $ganachePort
}

# Chain
get_chain_id () {
    chainId=0

    case $1 in 
        "avax")
            chainId=43115
        ;;
        "bnb")
            chainId=57
        ;;
    esac

    echo $chainId
}

# Mainnet fork instantiation
run_mainnet_fork () {
    chainId=$(get_chain_id $1)
    ganachePort=$(ganache_port $1)
    
    ganache \
        --server.host=0.0.0.0 \
        --chain.chainId=$chainId \
        --chain.networkId=$chainId \
        --wallet.defaultBalance=1000000 \
        --fork=$2 \
        --server.port=$ganachePort \
        --detach
}