#!/bin/sh

cp .env.prod-eth .env
source .env

forge script script/AddPaymentToken.s.sol:AddPaymentToken --rpc-url $RPC_URL --broadcast -vvv
