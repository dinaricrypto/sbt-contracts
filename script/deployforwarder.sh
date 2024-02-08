#!/bin/sh

cp .env.prod-eth .env
source .env

forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url $RPC_URL -vvv --broadcast --verify
