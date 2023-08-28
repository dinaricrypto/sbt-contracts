#!/bin/sh

source .env

forge script script/UpdateTokenCheck.s.sol:UpdateTokenCheckScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
