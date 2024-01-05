#!/bin/sh

cp .env.prod .env
source .env

forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url $RPC_URL -vvvv --broadcast --verify
