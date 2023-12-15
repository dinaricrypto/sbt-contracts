#!/bin/sh

cp .env.stage .env
source .env

forge script script/RenameTokens.s.sol:RenameTokens --rpc-url $RPC_URL -vvvv --broadcast
