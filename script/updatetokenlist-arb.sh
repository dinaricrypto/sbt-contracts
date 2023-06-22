#!/bin/sh

source .env

forge script script/UpdateTokenList.s.sol:UpdateTokenListScript --rpc-url $ARB_URL --etherscan-api-key $ARBISCAN_API_KEY --broadcast -vvvv
