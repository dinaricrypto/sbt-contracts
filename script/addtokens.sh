#!/bin/sh

cp .env.sandbox .env
source .env

forge script script/AddTokens.s.sol:AddTokens --rpc-url $RPC_URL --broadcast --slow -vvv
