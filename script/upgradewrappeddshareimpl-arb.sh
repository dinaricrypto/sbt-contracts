#!/bin/sh

cp .env.prod .env
source .env

forge script script/UpgradeWrappedDShareImpl.s.sol:UpgradeWrappedDShareImpl --rpc-url $RPC_URL -vvvv --broadcast --verify
