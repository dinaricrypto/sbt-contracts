#!/bin/sh

cp .env.eth-sepolia .env
source .env

forge script script/AddPaymentTokens.s.sol:AddPaymentTokens --rpc-url $RPC_URL --broadcast -vvvv

cp .env.prod .env
source .env

forge script script/AddPaymentTokens.s.sol:AddPaymentTokens --rpc-url $RPC_URL --broadcast -vvvv

cp .env.prod-eth .env
source .env

forge script script/AddPaymentTokens.s.sol:AddPaymentTokens --rpc-url $RPC_URL --broadcast -vvvv
