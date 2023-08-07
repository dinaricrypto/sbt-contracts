#!/bin/sh

source .env

forge script script/ConfigDiv.s.sol:ConfigDivScript --rpc-url $ARB_URL --broadcast -vvvv
