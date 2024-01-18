#!/bin/sh

cp .env.stage .env
source .env

forge script script/SetFees.s.sol:SetFees --rpc-url $RPC_URL --broadcast -vvv

cp .env.sandbox .env
source .env

forge script script/SetFees.s.sol:SetFees --rpc-url $RPC_URL --broadcast -vvv

cp .env.prod .env
source .env

forge script script/SetFees.s.sol:SetFees --rpc-url $RPC_URL --broadcast -vvv
