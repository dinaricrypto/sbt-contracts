#!/bin/sh

cp .env.blast-sepolia .env
source .env

forge script script/Mint.s.sol:Mint --rpc-url $RPC_URL --broadcast -vvvv
