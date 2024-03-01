#!/bin/sh

cp .env.blast-sepolia .env
source .env

forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvvv
# forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL --verifier blockscout -vvvv --broadcast --verify

