#!/bin/sh

source .env

forge script script/DeployDShareFactory.s.sol:DeployDshareFactoryScript --rpc-url $RPC_URL --etherscan-api-key $ARBISCAN_API_KEY --broadcast --verify -vvvv