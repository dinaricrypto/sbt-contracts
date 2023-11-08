#!/bin/sh

source .env

forge test -f $RPC_URL --match-path test/forwarder/**/\* -vvv