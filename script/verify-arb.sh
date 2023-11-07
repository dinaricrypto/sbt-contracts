#!/bin/sh

source .env

forge verify-contract --chain-id 42161 --watch --constructor-args $(cast abi-encode "constructor(address)" "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612") 0x14D3498e4816c2B8F017677356dca051e28a33c8 src/forwarder/Forwarder.sol:Forwarder
