#!/bin/sh

cp .env.prod-kinto .env
source .env

forge script script/kinto/CreateOrder.s.sol:CreateOrder --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation
