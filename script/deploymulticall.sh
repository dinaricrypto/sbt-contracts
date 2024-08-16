#!/bin/sh

cp .env.prod-kinto .env
source .env

forge script script/DeployMulticall.s.sol:DeployMulticall --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation
