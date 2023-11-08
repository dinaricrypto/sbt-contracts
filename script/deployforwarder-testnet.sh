#!/bin/sh

source .env

forge script script/DeployForwarder.s.sol:DeployForwarderScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
