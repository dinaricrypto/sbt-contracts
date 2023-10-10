#!/bin/sh

source .env

forge script script/DeployAllSandbox.s.sol:DeployAllSandboxScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
