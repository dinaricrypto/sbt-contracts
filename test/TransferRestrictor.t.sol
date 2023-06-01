// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/TransferRestrictor.sol";

contract TransferRestrictorTest is Test {
    event KycSet(address indexed account, ITransferRestrictor.KycType kycType);
    event KycReset(address indexed account);
    event Banned(address indexed account);
    event UnBanned(address indexed account);

    TransferRestrictor public restrictor;

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
    }

    function testSetResetKyc(address account, uint8 kycInt) public {
        vm.assume(kycInt < 3);
        ITransferRestrictor.KycType kycType = ITransferRestrictor.KycType(kycInt);

        vm.expectEmit(true, true, true, true);
        emit KycSet(account, kycType);
        restrictor.setKyc(account, kycType);
        assertEq(uint8(restrictor.getUserInfo(account).kycType), kycInt);
        if (kycInt > 0) {
            assertTrue(restrictor.isKyc(account));
        }

        vm.expectEmit(true, true, true, true);
        emit KycReset(account);
        restrictor.resetKyc(account);
        assertEq(uint8(restrictor.getUserInfo(account).kycType), uint8(ITransferRestrictor.KycType.NONE));
    }

    function testBanUnban(address account) public {
        vm.expectEmit(true, true, true, true);
        emit Banned(account);
        restrictor.ban(account);
        assertEq(restrictor.isBanned(account), true);

        vm.expectEmit(true, true, true, true);
        emit UnBanned(account);
        restrictor.unBan(account);
        assertEq(restrictor.isBanned(account), false);
    }
}
