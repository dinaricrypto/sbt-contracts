#!/bin/sh

forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation --verifier blockscout --verifier-url https://phoenix-explorer.plumenetwork.xyz/api\? --verify
