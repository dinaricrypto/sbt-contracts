#!/bin/sh

cp .env.prod-arb .env
source .env

forge script script/SetPaymentTokens.s.sol:SetPaymentTokens --rpc-url $RPC_URL -vvvv --broadcast
