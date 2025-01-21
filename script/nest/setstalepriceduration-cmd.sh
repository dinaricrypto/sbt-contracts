#!/bin/sh

forge script ./script/nest/SetStalePriceDuration.s.sol:SetStalePriceDuration --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation
