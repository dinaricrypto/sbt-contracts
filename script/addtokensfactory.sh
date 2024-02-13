#!/bin/sh

cp .env.prod-arb .env
source .env

forge script script/AddTokensFactory.s.sol:AddTokensFactory --rpc-url $RPC_URL --broadcast -vvv
