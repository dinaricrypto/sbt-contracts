#!/bin/sh

source .env

forge script script/ReplaceFees.s.sol:ReplaceFeesScript --rpc-url $TEST_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
