#!/bin/sh

cp .env.prod-arb .env
source .env

forge test -f $RPC_URL --match-path test/fork/**/\* -vvv