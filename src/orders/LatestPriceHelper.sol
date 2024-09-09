// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import "./IOrderProcessor.sol";

contract LatestPriceHelper {
    function aggregateLatestPriceFromProcessor(address processor, address token, address[] calldata paymentTokens)
        external
        view
        returns (IOrderProcessor.PricePoint memory latestPricePoint)
    {
        latestPricePoint = IOrderProcessor.PricePoint({blocktime: 0, price: 0});
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            IOrderProcessor.PricePoint memory pricePoint =
                IOrderProcessor(processor).latestFillPrice(token, paymentTokens[i]);
            if (pricePoint.blocktime > latestPricePoint.blocktime) {
                latestPricePoint = pricePoint;
            }
        }
    }
}
