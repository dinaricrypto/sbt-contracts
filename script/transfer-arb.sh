#!/bin/sh

source .env

forge script script/Transfer.s.sol:TransferScript --rpc-url $RPC_URL --broadcast -vvvv
