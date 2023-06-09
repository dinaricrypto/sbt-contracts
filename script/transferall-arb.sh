#!/bin/sh

source .env

forge script script/TransferAll.s.sol:TransferAllScript --rpc-url $ARB_URL --broadcast -vvvv
# cast send --rpc-url $ARB_URL --private-key $SENDER_KEY --value $SEND_AMOUNT $TO
