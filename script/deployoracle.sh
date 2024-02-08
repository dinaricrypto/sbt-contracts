#!/bin/sh

cp .env.eth-sepolia .env
source .env

forge script script/DeployOracle.s.sol:DeployOracle --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.arb-sepolia .env
source .env

forge script script/DeployOracle.s.sol:DeployOracle --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.plume-sepolia .env
source .env

forge script script/DeployOracle.s.sol:DeployOracle --rpc-url $RPC_URL -vvv --broadcast --verify
