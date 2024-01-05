#!/bin/sh

cp .env.prod .env
source .env

forge script script/DeployFillRouter.s.sol:DeployFillRouter --rpc-url $RPC_URL -vvvv --broadcast --verify
