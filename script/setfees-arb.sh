#!/bin/sh

source .env

forge script script/SetFees.s.sol:SetFeesScript --rpc-url $ARB_URL --broadcast -vvvv
