#!/bin/sh

cp .env-kinto-stage .env
source .env

forge script script/kinto/ApproveApps.s.sol:ApproveApps --rpc-url $RPC_URL -vvvv --broadcast --skip-simulation
