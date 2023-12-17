#!/bin/sh

cp .env.prod .env
source .env

forge script script/RenameTokens.s.sol:RenameTokens --rpc-url $RPC_URL -vvvv --broadcast
