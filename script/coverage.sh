#!/bin/sh

cp .env.prod-arb .env
source .env

forge coverage -f $RPC_URL --report lcov && genhtml --branch-coverage --dark-mode -o ./coverage/ lcov.info
