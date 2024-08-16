#!/bin/sh

cp .env.sandbox .env
source .env

forge script script/Order.s.sol:Order --rpc-url $RPC_URL -vvv --broadcast
