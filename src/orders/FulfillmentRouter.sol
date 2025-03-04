// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {MulticallUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {IVault} from "./IVault.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";
import {ControlledUpgradeable} from "../deployment/ControlledUpgradeable.sol";

/// @notice Specialized multicall for fulfilling orders with vault funds.
/// @dev Uses vault to remove the need for operator wallets to hold (non-gas) funds.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/FulfillmentRouter.sol)
/// @title FulfillmentRouter
/// @notice Specialized multicall for fulfilling orders with vault funds
/// @dev Uses vault to remove the need for operator wallets to hold (non-gas) funds
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/FulfillmentRouter.sol)
contract FulfillmentRouter is ControlledUpgradeable, MulticallUpgradeable {
    using SafeERC20 for IERC20;

    error BuyFillsNotSupported();
    error OnlyForBuyOrders();

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    ///--------------------- VERSION ---------------------///

    /// @notice Returns contract version as uint8
    /// @return Version number
    function version() public view override returns (uint8) {
        return 1;
    }

    /// @notice Returns contract version as string
    /// @return Version string
    function publicVersion() public view override returns (string memory) {
        return "1.0.0";
    }

    ///--------------------- INITIALIZATION ---------------------///

    /// @notice Initialize the contract
    /// @param initialOwner Address of contract owner
    /// @param upgrader Address authorized to upgrade contract
    function initialize(address initialOwner, address upgrader) public reinitializer(version()) {
        __ControlledUpgradeable_init(initialOwner, upgrader);
        __Multicall_init_unchained();
    }

    /// @notice Reinitialize the contract
    /// @param upgrader Address authorized to upgrade contract
    function reinitialize(address upgrader) public reinitializer(version()) {
        grantRole(UPGRADER_ROLE, upgrader);
    }

    ///--------------------- CORE FUNCTIONS ---------------------///

    /// @notice Fill a sell order using vault funds
    /// @param orderProcessor Address of order processor contract
    /// @param vault Address of vault contract
    /// @param order Order data
    /// @param fillAmount Amount to fill
    /// @param receivedAmount Amount received from fill
    /// @param fees Fee amount
    function fillOrder(
        address orderProcessor,
        address vault,
        IOrderProcessor.Order calldata order,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 fees
    ) external onlyRole(OPERATOR_ROLE) {
        if (!order.sell) revert BuyFillsNotSupported();

        // withdraw payment token from vault
        IVault(vault).withdrawFunds(IERC20(order.paymentToken), address(this), receivedAmount);
        // fill order with payment token
        IERC20(order.paymentToken).safeIncreaseAllowance(orderProcessor, receivedAmount);
        IOrderProcessor(orderProcessor).fillOrder(order, fillAmount, receivedAmount, fees);
    }

    /// @notice Cancel a buy order and return funds to vault
    /// @param orderProcessor Address of order processor
    /// @param order Order data
    /// @param vault Vault address
    /// @param orderId ID of order to cancel
    /// @param reason Cancellation reason
    function cancelBuyOrder(
        address orderProcessor,
        IOrderProcessor.Order calldata order,
        address vault,
        uint256 orderId,
        string calldata reason
    ) external onlyRole(OPERATOR_ROLE) {
        if (order.sell) revert OnlyForBuyOrders();
        // get unfilledAmount
        uint256 unfilledAmount = IOrderProcessor(orderProcessor).getUnfilledAmount(orderId);

        if (unfilledAmount > 0) {
            // withdraw payment token from vault
            IVault(vault).withdrawFunds(IERC20(order.paymentToken), address(this), unfilledAmount);
            IERC20(order.paymentToken).safeIncreaseAllowance(orderProcessor, unfilledAmount);
            IOrderProcessor(orderProcessor).cancelOrder(order, reason);
        }
    }
}
