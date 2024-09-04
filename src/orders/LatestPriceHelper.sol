// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import "./IOrderProcessor.sol";

import "solady/src/auth/Ownable.sol";

contract LatestPriceHelper is Ownable {
    address[] public paymentTokens;

    function setPaymentTokens(address[] memory _paymentTokens) external onlyOwner {
        paymentTokens = _paymentTokens;
    }

    function aggregateLatestPriceFromProcessor(address processor, address token)
        external
        view
        returns (IOrderProcessor.PricePoint memory latestPricePoint)
    {
        address[] memory _paymentTokens = paymentTokens;

        latestPricePoint = IOrderProcessor.PricePoint({blocktime: 0, price: 0});
        for (uint256 i = 0; i < _paymentTokens.length; i++) {
            IOrderProcessor.PricePoint memory pricePoint =
                IOrderProcessor(processor).latestFillPrice(token, _paymentTokens[i]);
            if (pricePoint.blocktime > latestPricePoint.blocktime) {
                latestPricePoint = pricePoint;
            }
        }
    }
}
