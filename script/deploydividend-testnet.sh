#!/bin/sh

source .env

forge script script/DeployDividend.s.sol:DeployDividendScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
