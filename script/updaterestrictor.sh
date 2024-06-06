#!/bin/sh

cp .env.prod-arb .env
source .env

forge script script/UpdateRestrictor.s.sol:UpdateRestrictor --rpc-url $RPC_URL -vvvv --broadcast
