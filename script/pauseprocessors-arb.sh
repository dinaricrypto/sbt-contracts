#!/bin/sh

source .env

forge script script/PauseProcessors.s.sol:PauseProcessorsScript --rpc-url $ARB_URL --broadcast -vvvv
