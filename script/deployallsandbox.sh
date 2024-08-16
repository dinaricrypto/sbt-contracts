#!/bin/sh

cp .env.sandbox-plume-sepolia .env
source .env

forge script script/DeployAllSandbox.s.sol:DeployAllSandbox --rpc-url $RPC_URL -vvvv --broadcast --slow --skip-simulation --legacy --verifier blockscout --verify
