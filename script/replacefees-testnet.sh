#!/bin/sh

source .env

forge script script/ReplaceFees.s.sol:ReplaceFeesScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
