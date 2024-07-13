#!/bin/sh

cp .env.sandbox .env
source .env

forge script script/AddTokens.s.sol:AddTokensScript --rpc-url $RPC_URL --broadcast --slow -vvvv
