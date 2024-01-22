#!/bin/sh

cp .env.stage .env
source .env

forge script script/DeployFactory.s.sol:DeployFactory --rpc-url $RPC_URL -vvv --broadcast --verify
