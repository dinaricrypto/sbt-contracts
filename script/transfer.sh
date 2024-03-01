#!/bin/sh

cp .env.prod-arb .env
source .env

forge script script/Transfer.s.sol:Transfer --rpc-url $RPC_URL --broadcast -vvvv
