// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IOrderBridge} from "../../src/issuer/IOrderBridge.sol";
import {PriceAttestationConsumer} from "./PriceAttestationConsumer.sol";
import {Nonces} from "../common/Nonces.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IForwarder} from "./IForwarder.sol";

/// @notice Contract for paying gas fees for users and forwarding meta transactions to OrderProcessor contracts.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/OrderProcessor.sol)
contract Forwarder is IForwarder, Ownable, PriceAttestationConsumer, Nonces, Multicall, SelfPermit, ReentrancyGuard {
    using SafeERC20 for IERC20Permit;
    using SafeERC20 for IERC20;
    using Address for address;

    /// ------------------------------- Types -------------------------------

    struct SupportedModules {
        address buyOrderIssuer;
        address directBuyIssuer;
        address sellOrderProcessor;
        address limitBuyIssuer;
        address limitSellProcessor;
    }

    error UserNotRelayer();
    error InvalidSigner();
    error InvalidAmount();
    error ExpiredRequest();
    error UnsupportedCall();
    error InvalidModuleAddress();
    error FeeTooHigh();

    event RelayerSet(address indexed relayer, bool isRelayer);
    event BuyOrderIssuerSet(address indexed buyOrderIssuer);
    event DirectBuyIssuerSet(address indexed directBuyIssuer);
    event SellOrderProcessorSet(address indexed sellOrderProcessor);
    event LimitBuyIssuerSet(address indexed limitBuyIssuer);
    event LimitSellProcessorSet(address indexed limitSellProcessor);
    event FeeUpdated(uint256 feeBps);
    event CancellationGasCostUpdated(uint256 gas);

    /// ------------------------------- Constants -------------------------------

    bytes private constant SIGNEDPRICEATTESTATION_TYPE = abi.encodePacked(
        "PriceAttestation(address token,uint256 price,uint64 timestamp,uint256 chainId,bytes signature)"
    );
    bytes32 private constant SIGNEDPRICEATTESTATION_TYPEHASH = keccak256(SIGNEDPRICEATTESTATION_TYPE);
    bytes private constant FORWARDREQUEST_TYPE = abi.encodePacked(
        "ForwardRequest(address user,address to,bytes data,uint64 deadline,uint256 nonce,PriceAttestation paymentTokenOraclePrice)",
        SIGNEDPRICEATTESTATION_TYPE
    );
    bytes32 private constant FORWARDREQUEST_TYPEHASH = keccak256(FORWARDREQUEST_TYPE);

    /// ------------------------------- Storage -------------------------------

    /// @inheritdoc IForwarder
    uint16 public feeBps;

    /// @inheritdoc IForwarder
    uint256 public cancellationGasCost;

    /// @notice The set of supported modules.
    SupportedModules public supportedModules;

    /// @inheritdoc IForwarder
    mapping(address => bool) public isRelayer;

    /// @inheritdoc IForwarder
    mapping(bytes32 => address) public orderSigner;

    /// ------------------------------- Modifiers -------------------------------

    modifier onlyRelayer() {
        if (!isRelayer[msg.sender]) {
            revert UserNotRelayer();
        }
        _;
    }

    /// ------------------------------- Initialization -------------------------------

    /// @notice Constructs the Forwarder contract.
    /// @dev Initializes the domain separator used for EIP-712 compliant signature verification.
    /// @param _priceRecencyThreshold The maximum age of a price oracle attestation that is considered valid.
    constructor(uint64 _priceRecencyThreshold)
        PriceAttestationConsumer(_priceRecencyThreshold)
        EIP712("Forwarder", "1")
    {
        feeBps = 0;
        cancellationGasCost = 0;
    }

    /// ------------------------------- Administration -------------------------------

    /// @notice Sets Relayer address state.
    /// @dev Only callable by the contract owner.
    function setRelayer(address newRelayer, bool _isRelayer) external onlyOwner {
        isRelayer[newRelayer] = _isRelayer;
        emit RelayerSet(newRelayer, _isRelayer);
    }

    /// @notice Sets the address of the BuyOrderIssuer contract.
    /// @dev Only callable by the contract owner.
    function setBuyOrderIssuer(address buyOrderIssuer) external onlyOwner {
        supportedModules.buyOrderIssuer = buyOrderIssuer;
        emit BuyOrderIssuerSet(buyOrderIssuer);
    }

    /// @notice Sets the address of the DirectBuyIssuer contract.
    /// @dev Only callable by the contract owner.
    function setDirectBuyIssuer(address directBuyIssuer) external onlyOwner {
        supportedModules.directBuyIssuer = directBuyIssuer;
        emit DirectBuyIssuerSet(directBuyIssuer);
    }

    /// @notice Sets the address of the SellOrderProcessor contract.
    /// @dev Only callable by the contract owner.
    function setSellOrderProcessor(address sellOrderProcessor) external onlyOwner {
        supportedModules.sellOrderProcessor = sellOrderProcessor;
        emit SellOrderProcessorSet(sellOrderProcessor);
    }

    /// @notice Sets the address of the LimitBuyIssuer contract.
    /// @dev Only callable by the contract owner.
    function setLimitBuyIssuer(address limitBuyIssuer) external onlyOwner {
        supportedModules.limitBuyIssuer = limitBuyIssuer;
        emit LimitBuyIssuerSet(limitBuyIssuer);
    }

    /// @notice Sets the address of the LimitSellProcessor contract.
    /// @dev Only callable by the contract owner.
    function setLimitSellProcessor(address limitSellProcessor) external onlyOwner {
        supportedModules.limitSellProcessor = limitSellProcessor;
        emit LimitSellProcessorSet(limitSellProcessor);
    }

    /// @notice Updates the fee rate.
    /// @dev Only callable by the contract owner.
    /// @param newFeeBps The new fee rate in basis points.
    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > 10000) revert FeeTooHigh();

        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }

    /// @notice Updates the cancellation gas cost estimate.
    /// @dev Only callable by the contract owner.
    /// @param newCancellationGasCost The new cancellation fee.
    function setCancellationGasCost(uint256 newCancellationGasCost) external onlyOwner {
        cancellationGasCost = newCancellationGasCost;
        emit CancellationGasCostUpdated(newCancellationGasCost);
    }

    /// ------------------------------- Forwarding -------------------------------

    /// @inheritdoc IForwarder
    function forwardFunctionCall(ForwardRequest calldata metaTx) external onlyRelayer nonReentrant {
        uint256 gasStart = gasleft();
        _validateForwardRequest(metaTx);

        // Get the function selector
        bytes4 functionSelector = bytes4(metaTx.data[:4]);
        // Check call
        if (functionSelector == IOrderBridge.requestOrder.selector) {
            // Check if function selector is request Order to approve quantityIn
            // Get order from data
            (IOrderBridge.Order memory order) = abi.decode(metaTx.data[4:], (IOrderBridge.Order));
            _requestOrderPreparation(order, metaTx.user, metaTx.to);
        } else if (functionSelector == IOrderBridge.requestCancel.selector) {
            // Check if cancel request is from the original order signer
            // TODO: verify that orderprocessor has approved this as forwarder
            // Get data from metaTx
            (address recipient, uint256 index) = abi.decode(metaTx.data[4:], (address, uint256));
            bytes32 orderId = IOrderBridge(metaTx.to).getOrderId(recipient, index);
            if (orderSigner[orderId] != metaTx.user) revert InvalidSigner();
        } else {
            revert UnsupportedCall();
        }

        // execute low level call to issuer
        bytes memory result = metaTx.to.functionCall(metaTx.data);

        if (functionSelector == IOrderBridge.requestOrder.selector) {
            uint256 id = abi.decode(result, (uint256));
            // get order ID
            bytes32 orderId = IOrderBridge(metaTx.to).getOrderId(metaTx.user, id);
            orderSigner[orderId] = metaTx.user;
        }

        // handle transaction payment
        if (functionSelector == IOrderBridge.requestOrder.selector) {
            _handlePayment(
                metaTx.user, metaTx.paymentTokenOraclePrice.token, metaTx.paymentTokenOraclePrice.price, gasStart
            );
        }
    }

    /**
     * @dev Validates the forward request by checking the oracle price, target address, deadline,
     *      verifying the price attestation, checking the nonce, and ensuring that the signer of the request is valid.
     * @param metaTx The meta transaction containing the user address, target contract, encoded function call data,
     *      deadline, nonce, payment token oracle price, and the signature components (v, r, s).
     */
    function _validateForwardRequest(ForwardRequest calldata metaTx) internal {
        if (metaTx.to == address(0)) revert InvalidModuleAddress();
        if (metaTx.deadline < block.timestamp) revert ExpiredRequest();

        _verifyPriceAttestation(metaTx.paymentTokenOraclePrice);

        // slither-disable-next-line unused-return
        _useCheckedNonce(metaTx.user, metaTx.nonce);

        bytes32 typedDataHash = _hashTypedDataV4(forwardRequestHash(metaTx));

        address signer = ECDSA.recover(typedDataHash, metaTx.signature);
        if (signer != metaTx.user) revert InvalidSigner();
    }

    function _signedPriceAttestationHash(PriceAttestation calldata priceAttestation) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SIGNEDPRICEATTESTATION_TYPEHASH,
                priceAttestation.token,
                priceAttestation.price,
                priceAttestation.timestamp,
                priceAttestation.chainId,
                keccak256(priceAttestation.signature)
            )
        );
    }

    /// @inheritdoc IForwarder
    function forwardRequestHash(ForwardRequest calldata metaTx) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                FORWARDREQUEST_TYPEHASH,
                metaTx.user,
                metaTx.to,
                keccak256(metaTx.data),
                metaTx.deadline,
                metaTx.nonce,
                _signedPriceAttestationHash(metaTx.paymentTokenOraclePrice)
            )
        );
    }

    /**
     * @dev Prepares an order request by transferring tokens from the user to this contract,
     *      and approving the specified target contract to spend the tokens.
     *      This function supports preparation for both buying and selling orders.
     *
     * @param order The details of the order, including payment and asset tokens, and the quantity.
     * @param user The address of the user initiating the order.
     * @param target The address of the target contract (e.g. buyOrderIssuer or sellOrderProcessor) that will execute the order.
     */
    function _requestOrderPreparation(IOrderBridge.Order memory order, address user, address target) internal {
        // store order to mapping

        // Pull tokens from user and approve module to spend
        if (
            target == supportedModules.buyOrderIssuer || target == supportedModules.directBuyIssuer
                || target == supportedModules.limitBuyIssuer
        ) {
            // slither-disable-next-line arbitrary-send-erc20
            IERC20(order.paymentToken).safeTransferFrom(user, address(this), order.quantityIn);
            IERC20(order.paymentToken).safeIncreaseAllowance(target, order.quantityIn);
        } else if (target == supportedModules.sellOrderProcessor || target == supportedModules.limitSellProcessor) {
            // slither-disable-next-line arbitrary-send-erc20
            IERC20(order.assetToken).safeTransferFrom(user, address(this), order.quantityIn);
            IERC20(order.assetToken).safeIncreaseAllowance(target, order.quantityIn);
        } else {
            // Service not available for other contracts
            revert InvalidModuleAddress();
        }
    }

    /**
     * @dev Handles the payment of transaction fees in the form of tokens. Calculates the
     *      gas used for the transaction and transfers the equivalent amount in tokens from
     *      the user to the relayer.
     *
     * @param user The address of the user who is paying the transaction fees.
     * @param paymentToken The address of the ERC20 token used for payment.
     * @param paymentTokenPrice The price of the payment token in terms of wei.
     * @param gasStart The amount of gas at the start of the transaction.
     */
    function _handlePayment(address user, address paymentToken, uint256 paymentTokenPrice, uint256 gasStart) internal {
        uint256 gasUsed = gasStart - gasleft();
        // TODO: Test that Arbitrum returns reasonable gasUsed and gasprice values
        uint256 totalGasCostInWei = (gasUsed + cancellationGasCost) * tx.gasprice;
        uint256 paymentAmount = totalGasCostInWei / paymentTokenPrice;

        // Calculate fee amount
        // slither-disable-next-line divide-before-multiply
        uint256 fee = (paymentAmount * feeBps) / 10000;

        // Transfer the payment for gas fees
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(paymentToken).safeTransferFrom(user, msg.sender, paymentAmount + fee);
    }

    function getSupportedModules() external view returns (SupportedModules memory) {
        return supportedModules;
    }

    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
