#!/bin/sh

source .env

forge script script/DeployRestrictorLocked.s.sol:DeployRestrictorLockedScript --rpc-url $RPC_URL --broadcast --verify -vvvv
