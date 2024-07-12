#!/bin/sh

# cp .env.blast-sepolia .env
# source .env

# forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.sandbox .env
source .env

# forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv
forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv --broadcast --slow --verify

