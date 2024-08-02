#!/bin/sh

cp .env.prod-arb .env
source .env

forge script script/AddTokensFromFactory.s.sol:AddTokensFromFactory --rpc-url $RPC_URL --broadcast --slow -vvv
