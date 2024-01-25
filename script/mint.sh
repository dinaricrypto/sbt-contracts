#!/bin/sh

cp .env.eth-sepolia .env
source .env

forge script script/Mint.s.sol:Mint --rpc-url $RPC_URL --broadcast -vvvv
