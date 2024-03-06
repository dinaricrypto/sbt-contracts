#!/bin/sh

# cp .env.blast-sepolia .env
# source .env

# forge script script/Permit.s.sol:Permit --rpc-url $RPC_URL -vvv

cp .env.prod-blast .env
source .env

forge script script/Permit.s.sol:Permit --rpc-url $RPC_URL -vvv
