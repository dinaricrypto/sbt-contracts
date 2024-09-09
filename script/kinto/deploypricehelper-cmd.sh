#!/bin/sh

forge script script/DeployPriceHelper.s.sol:DeployPriceHelper --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation --verify --verifier blockscout --verifier-url https://explorer.kinto.xyz/api
