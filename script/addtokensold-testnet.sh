#!/bin/sh

source .env

forge script script/AddTokensOld.s.sol:AddTokensOldScript --rpc-url $TEST_RPC_URL --broadcast -vvvv
