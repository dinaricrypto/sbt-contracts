#!/bin/sh

cp .env.blast-sepolia .env
source .env

# forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv
forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL --verifier blockscout -vvv --broadcast --verify

