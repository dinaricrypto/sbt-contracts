#!/bin/sh

cp .env.prod .env
source .env

forge script script/AddTokens.s.sol:AddTokensScript --rpc-url $RPC_URL --broadcast -vvvv
