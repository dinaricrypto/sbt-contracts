#!/bin/sh

cp .env.prod .env
source .env

forge script script/UpgradeOrderProcessor.s.sol:UpgradeOrderProcessor --rpc-url $RPC_URL -vvvv --broadcast --verify
