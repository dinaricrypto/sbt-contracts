#!/bin/sh

source .env

forge script script/DeployRestrictor.s.sol:DeployRestrictorScript --rpc-url $RPC_ARBITRUM --etherscan-api-key $ARBISCAN_API_KEY --broadcast --verify -vvvv
