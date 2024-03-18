#!/bin/sh

# cp .env.blast-sepolia .env
# source .env

# forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.prod-blast .env
source .env

# forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv
forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv --broadcast --verify

