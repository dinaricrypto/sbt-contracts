#!/bin/sh

source .env

forge script script/HaltOrders.s.sol:HaltOrdersScript --rpc-url $RPC_URL --broadcast -vvvv
