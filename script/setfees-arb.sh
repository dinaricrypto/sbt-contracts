#!/bin/sh

source .env

forge script script/SetFees.s.sol:SetFeesScript --rpc-url $RPC_ARBITRUM --broadcast -vvvv
