#!/bin/sh

source .env

forge script script/DeployAll.s.sol:DeployAllScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
