#!/bin/sh

forge script ./script/nest/ProcessSubmittedOrders.s.sol:ProcessSubmittedOrders --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation
