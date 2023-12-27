#!/bin/sh

cp .env.prod .env
source .env

forge script script/Order.s.sol:Order --rpc-url $RPC_URL --broadcast -vvvv
