#!/bin/sh

source .env

forge script script/DeployRestrictor.s.sol:DeployRestrictorScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
