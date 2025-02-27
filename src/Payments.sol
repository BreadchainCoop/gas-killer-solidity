// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PaymentContract
 * @notice This simple contract collects the 0.1 ETH fee from callers.
 */
contract PaymentContract {
    address public owner;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public erc20Balances;

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Called by VotingContract to deposit exactly 0.1 ETH.
     */
    function deposit() external payable {
        require(msg.value == 0.1 ether, "Must send exactly 0.1 ETH");
        balances[msg.sender] += msg.value;
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

    /**
     * @dev Allows users to deposit ERC-20 tokens.
     * @param token The address of the ERC-20 token contract.
     * @param amount The amount of tokens to deposit.
     */
    function depositERC20(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        erc20Balances[token][msg.sender] += amount;
    }
}
