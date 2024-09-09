#!/bin/sh

forge script ./script/DeployPriceHelper.s.sol:DeployPriceHelper --rpc-url $RPC_URL -vvv --broadcast --slow --verify
