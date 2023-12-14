#!/bin/sh

cp .env.stage .env
source .env

forge script script/AddTokens.s.sol:AddTokensScript --rpc-url $RPC_URL --broadcast -vvvv
