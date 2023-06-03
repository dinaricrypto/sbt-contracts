#!/bin/sh

source .env

forge script script/AddTokens.s.sol:AddTokensScript --rpc-url $TEST_RPC_URL --broadcast -vvvv
