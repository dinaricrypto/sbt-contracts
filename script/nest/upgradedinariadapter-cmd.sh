#!/bin/sh

forge script ./script/nest/UpgradeDinariAdapter.s.sol:UpgradeDinariAdapter --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation --verifier blockscout --verify
