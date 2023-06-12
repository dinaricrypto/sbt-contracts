#!/bin/sh

source .env

forge script script/UpgradeIssuer.s.sol:UpgradeIssuerScript --rpc-url $TEST_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
