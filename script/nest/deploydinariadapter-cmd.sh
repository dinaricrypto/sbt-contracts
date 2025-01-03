#!/bin/sh

forge script ./script/nest/DeployDinariAdapter.s.sol:DeployDinariAdapter --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation --verifier blockscout --verify
