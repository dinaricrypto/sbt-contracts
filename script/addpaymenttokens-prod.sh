#!/bin/sh

cp .env.prod .env
source .env

forge script script/AddPaymentTokens.s.sol:AddPaymentTokens --rpc-url $RPC_URL --broadcast -vvvv
