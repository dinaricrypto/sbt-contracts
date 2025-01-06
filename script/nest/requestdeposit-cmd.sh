#!/bin/sh

forge script ./script/nest/RequestDeposit.s.sol:RequestDeposit --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation
