// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title PaymentContract
 * @notice This simple contract collects the 0.1 ETH fee from callers.
 */
contract PaymentContract {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Called by VotingContract to deposit exactly 0.1 ETH.
     */
    function deposit() external payable {
        require(msg.value == 0.1 ether, "Must send exactly 0.1 ETH");
        // The 0.1 ETH now sits in this contract's balance.
        // You can track or emit events here as needed.
    }

    /**
     * @dev Allows the owner (deployer) to withdraw all collected fees.
     */
    function withdraw(address payable _to) external {
        require(msg.sender == owner, "Only owner can withdraw");
        uint256 balance = address(this).balance;
        (bool success, ) = _to.call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
