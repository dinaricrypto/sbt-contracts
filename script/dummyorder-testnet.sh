#!/bin/sh

source .env

forge script script/DummyOrder.s.sol:DummyOrderScript --rpc-url $ARBITRUM_GOERLI_RPC_URL --broadcast --verify -vvvv
