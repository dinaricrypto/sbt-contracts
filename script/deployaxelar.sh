#!/bin/sh

cp .env.prod-eth .env
source .env

forge script script/DeployAxelarManager.s.sol:DeployAxelarManager --rpc-url $RPC_URL -vvvv
