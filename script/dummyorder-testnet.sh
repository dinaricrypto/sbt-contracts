#!/bin/sh

source .env

forge script script/DummyOrder.s.sol:DummyOrderScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
