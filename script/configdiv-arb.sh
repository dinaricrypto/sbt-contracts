#!/bin/sh

source .env

forge script script/ConfigDiv.s.sol:ConfigDivScript --rpc-url $RPC_URL --broadcast -vvvv
