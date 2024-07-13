#!/bin/sh

cp .env.sandbox .env
source .env

forge script script/CreateOrder.s.sol:CreateOrder --rpc-url $RPC_URL --broadcast -vvv
