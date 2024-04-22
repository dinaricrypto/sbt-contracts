#!/bin/sh

cp .env.prod-arb .env
source .env

forge script script/AddTokens.s.sol:AddTokensScript --rpc-url $RPC_URL -vvv --resume
