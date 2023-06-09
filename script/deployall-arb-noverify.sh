#!/bin/sh

source .env

forge script script/DeployAll.s.sol:DeployAllScript --rpc-url $ARB_URL --broadcast -vvvv
