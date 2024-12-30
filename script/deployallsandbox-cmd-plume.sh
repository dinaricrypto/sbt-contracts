#!/bin/sh

forge script script/DeployAllSandbox.s.sol:DeployAllSandbox --rpc-url $RPC_URL -vvvv --broadcast --slow --skip-simulation --legacy --verifier blockscout --verify --verifier-url https://test-explorer.plumenetwork.xyz/api?
