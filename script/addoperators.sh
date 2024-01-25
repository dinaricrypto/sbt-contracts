#!/bin/sh

cp .env.prod .env
source .env

forge script script/AddOperators.s.sol:AddOperators --rpc-url $RPC_URL --broadcast -vvvv
