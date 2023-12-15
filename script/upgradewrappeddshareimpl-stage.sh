#!/bin/sh

cp .env.stage .env
source .env

forge script script/UpgradeWrappedDShareImpl.s.sol:UpgradeWrappedDShareImpl --rpc-url $RPC_URL -vvvv --broadcast --verify
