#!/bin/sh

forge inspect BuyOrderIssuer storage --pretty > storage/BuyOrderIssuer.txt
forge inspect DirectBuyIssuer storage --pretty > storage/DirectBuyIssuer.txt
forge inspect SellOrderProcessor storage --pretty > storage/SellOrderProcessor.txt
forge inspect LimitBuyIssuer storage --pretty > storage/LimitBuyIssuer.txt
forge inspect LimitSellProcessor storage --pretty > storage/LimitSellProcessor.txt
