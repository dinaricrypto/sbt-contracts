#!/bin/sh

source .env

forge script script/AddOperators.s.sol:AddOperatorsScript --rpc-url $TEST_RPC_URL --broadcast -vvvv
