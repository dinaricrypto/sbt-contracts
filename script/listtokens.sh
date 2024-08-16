#!/bin/sh

cp .env.prod-kinto .env
source .env

forge script script/ListTokens.s.sol:ListTokens --rpc-url $RPC_URL -vvv
