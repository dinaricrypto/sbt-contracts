#!/bin/sh

forge inspect BuyOrderIssuer storage --pretty > storage/BuyOrderIssuer.txt
forge inspect DirectBuyIssuer storage --pretty > storage/DirectBuyIssuer.txt
forge inspect SellOrderProcessor storage --pretty > storage/SellOrderProcessor.txt
