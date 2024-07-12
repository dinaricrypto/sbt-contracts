#!/bin/sh

cp .env.sandbox35 .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

# cp .env.prod-arb .env
# source .env

# forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

# cp .env.prod-blast .env
# source .env

# forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

# cp .env.prod-base .env
# source .env

# forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

# cp .env.prod-eth .env
# source .env

# forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --slow --verify