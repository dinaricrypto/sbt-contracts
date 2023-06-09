#!/bin/sh

source .env

forge script script/Transfer.s.sol:TransferScript --rpc-url $ARB_URL --broadcast -vvvv
