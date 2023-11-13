#!/bin/sh

source .env

forge script script/UpdateTokenNames.s.sol:UpdateTokenNamesScript --rpc-url $RPC_URL --broadcast -vvvv
