#!/bin/sh

cp .env.eth-sepolia .env
source .env

forge script script/DeployOracle.s.sol:DeployOracle --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.arb-sepolia .env
source .env

forge script script/DeployOracle.s.sol:DeployOracle --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.plume-sepolia .env
source .env

forge script script/DeployOracle.s.sol:DeployOracle  --legacy --skip-simulation --rpc-url $RPC_URL -vvv --verifier blockscout --broadcast --verify

cp .env.prod .env
source .env

forge script script/DeployOracle.s.sol:DeployOracle --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.prod-eth .env
source .env

forge script script/DeployOracle.s.sol:DeployOracle --rpc-url $RPC_URL -vvv --broadcast --verify

