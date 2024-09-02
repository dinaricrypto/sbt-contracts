#!/bin/sh

cp .env.staging-sepolia .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.staging-arb-sepolia .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify


cp .env.sandbox .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.prod-base .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.prod-eth .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --slow --verify

cp .env.prod-kinto .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation --verify --verifier blockscout --verifier-url https://explorer.kinto.xyz/api

cp .env.prod-arb .env
source .env

forge script script/UpgradeProcessor.s.sol:UpgradeProcessor --rpc-url $RPC_URL -vvv --broadcast --verify

