#!/bin/sh

source .env

forge script script/DeployTokenList.s.sol:DeployTokenListScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
