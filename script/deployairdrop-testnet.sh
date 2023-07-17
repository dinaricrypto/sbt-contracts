#!/bin/sh

source .env

forge script script/DeployAirdrop.s.sol:DeployAirdropScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
