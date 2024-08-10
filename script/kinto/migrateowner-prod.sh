#!/bin/sh

cp .env.prod-kinto .env
source .env

forge script script/kinto/MigrateOwner.s.sol:MigrateOwner --rpc-url $RPC_URL -vvv --broadcast --skip-simulation --slow
