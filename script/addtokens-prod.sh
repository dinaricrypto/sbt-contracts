#!/bin/sh

cp .env.prod-blast .env
source .env

forge script script/AddTokens.s.sol:AddTokensScript --rpc-url $RPC_URL -vvv --broadcast
