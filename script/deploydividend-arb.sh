#!/bin/sh

source .env

forge script script/DeployDividend.s.sol:DeployDividendScript --rpc-url $ARB_URL --etherscan-api-key $ARBISCAN_API_KEY --broadcast --verify -vvvv