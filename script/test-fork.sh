#!/bin/sh

cp .env.prod .env
source .env

forge test -f $RPC_URL --match-path test/forwarder/**/\* -vvv