#!/bin/sh

source .env

forge script script/DeployMockPaymentToken.s.sol:DeployMockPaymentTokenScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
