#!/bin/sh

source .env

forge script script/Mint.s.sol:MintScript --rpc-url $TEST_RPC_URL --broadcast -vvvv
