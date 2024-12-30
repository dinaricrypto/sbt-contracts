#!/bin/sh

forge script script/AddPaymentToken.s.sol:AddPaymentToken --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation --legacy
