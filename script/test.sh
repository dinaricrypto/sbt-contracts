#!/bin/sh

source .env

forge test -f $RPC_ARBITRUM -vvv
