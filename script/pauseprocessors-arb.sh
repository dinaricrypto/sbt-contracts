#!/bin/sh

source .env

forge script script/PauseProcessors.s.sol:PauseProcessorsScript --rpc-url $RPC_URL --broadcast -vvvv
