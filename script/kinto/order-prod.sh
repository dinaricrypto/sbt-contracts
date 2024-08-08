#!/bin/sh

cp .env-kinto-prod .env
source .env

forge script script/kinto/CreateOrder.s.sol:CreateOrder --rpc-url $RPC_URL -vvvv --broadcast --skip-simulation
