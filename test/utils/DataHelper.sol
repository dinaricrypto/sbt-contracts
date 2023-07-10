pragma solidity 0.8.19;

import {DividendAirdrop} from "../../src/dividend-airdrops/DividendAirdrop.sol";

// `DataHelper` is a utility contract for handling airdrop data and interacting with the DividendAirdrop test contract.
contract DataHelper {
    // State variables for airdrop addresses and corresponding amounts.
    address public airdropAddress0 = 0xB7E390864a90B7B923e9F9310c6f98aAFE43F707;
    address public airdropAddress1 = 0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8;
    address public airdropAddress2 = 0xEA694FdDe714fD979dE3EdF0f56aA9716B898EC8;

    uint256 public airdropAmount0 = 10000000000000000000000000;
    uint256 public airdropAmount1 = 20000000000000000000000000;
    uint256 public airdropAmount2 = 20000000000000000000000000;

    // Function to generate an array of bytes32 hashes representing airdrop data.
    function generateData(address _airdrop) internal view returns (bytes32[] memory data) {
        // Get the airdrop addresses and amounts.
        (address[] memory _user, uint256[] memory _amount) = getAirdropData();

        // Initialize the data array with the number of users.
        data = new bytes32[](_user.length);

        // Compute the hash for each user and corresponding amount, store it in the data array.
        for (uint256 i = 0; i < _user.length; i++) {
            data[i] = DividendAirdrop(_airdrop).hashLeaf(_user[i], _amount[i]);
        }
    }

    // Function to return arrays of airdrop addresses and amounts.
    function getAirdropData() public view returns (address[] memory, uint256[] memory) {
        // Initialize an array of airdrop addresses and set each element to the corresponding state variable.
        address[] memory _user = new address[](3);
        _user[0] = airdropAddress0;
        _user[1] = airdropAddress1;
        _user[2] = airdropAddress2;

        // Initialize an array of airdrop amounts and set each element to the corresponding state variable.
        uint256[] memory _amount = new uint256[](3);
        _amount[0] = airdropAmount0;
        _amount[1] = airdropAmount1;
        _amount[2] = airdropAmount2;

        // Return the arrays of airdrop addresses and amounts.
        return (_user, _amount);
    }
}
