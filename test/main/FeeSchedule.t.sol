// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {FeeSchedule} from "../../src/FeeSchedule.sol";
import {BuyProcessor} from "../../src/orders/BuyProcessor.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {FeeSchedule, IFeeSchedule} from "../../src/FeeSchedule.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import "../utils/mocks/MockdShare.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract FeeScheduleTest is Test {
    FeeSchedule feeSchedule;
    BuyProcessor issuer;
    TokenLockCheck tokenLockCheck;
    dShare token;
    MockToken paymentToken;

    uint256 userPrivateKey;
    address user;
    address constant treasury = address(4);
    address constant operator = address(3);

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);
        feeSchedule = new FeeSchedule();

        token = new MockdShare();
        paymentToken = new MockToken("Money", "$");

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(0));
        tokenLockCheck.setAsDShare(address(token));

        issuer = new BuyProcessor(address(this), treasury, 1 ether, 5_000, tokenLockCheck, feeSchedule);
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
    }

    function testSetFeeSchedule(uint64 _perOrderFee, uint24 _percentageRateFee) public {
        IFeeSchedule.Fee memory fee =
            IFeeSchedule.Fee({perOrderFee: _perOrderFee, percentageFeeRate: _percentageRateFee});
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        feeSchedule.setFees(user, fee, false);

        feeSchedule.setFees(user, fee, false);

        (uint24 percentageFeeRate, uint64 perOrderFee) = feeSchedule.getFees(user, false);
        assertEq(percentageFeeRate, _percentageRateFee);
        assertEq(perOrderFee, _perOrderFee);
    }

    function testSetZeroFees(bool _isZeroFee) public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        feeSchedule.setZeroFeeState(user, _isZeroFee);

        feeSchedule.setZeroFeeState(user, _isZeroFee);

        assertEq(feeSchedule.accountZeroFee(user), _isZeroFee);
    }

    function testEnableDisableFeeScheduleForAddress(uint64 _perOrderFee, uint24 _percentageRateFee) public {
        IFeeSchedule.Fee memory fee =
            IFeeSchedule.Fee({perOrderFee: _perOrderFee, percentageFeeRate: _percentageRateFee});

        (, uint24 percentageRateFee) = issuer.getFeeRatesForOrder(user, address(token), false);
        assertEq(percentageRateFee, issuer.percentageFeeRate());

        feeSchedule.setFees(user, fee, false);
        feeSchedule.setFees(user, fee, true);

        issuer.enableFeeScheduleForRequester(user);
        assertEq(issuer.userHasFeeSchedule(user), true);

        (, percentageRateFee) = issuer.getFeeRatesForOrder(user, address(token), false);
        assertEq(percentageRateFee, _percentageRateFee);
        assert(percentageRateFee != issuer.percentageFeeRate());

        feeSchedule.setZeroFeeState(user, true);

        (, percentageRateFee) = issuer.getFeeRatesForOrder(user, address(token), false);
        assertEq(percentageRateFee, 0);

        issuer.disableFeeScheduleForRequester(user);
        assertEq(issuer.userHasFeeSchedule(user), false);

        (, percentageRateFee) = issuer.getFeeRatesForOrder(user, address(token), false);
        assertEq(percentageRateFee, issuer.percentageFeeRate());
    }
}
