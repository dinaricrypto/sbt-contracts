#!/bin/sh

cp .env.staging-sepolia .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.staging-arb-sepolia .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify
