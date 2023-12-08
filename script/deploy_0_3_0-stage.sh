#!/bin/sh

cp .env.stage .env
source .env

forge script script/Deploy_0_3_0.s.sol:DeployScript --rpc-url $RPC_URL -vvv --broadcast --verify
