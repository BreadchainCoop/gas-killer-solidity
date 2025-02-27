// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@eigenlayer-middleware/interfaces/IServiceManager.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PaymentContract
 * @notice This contract collects fees and can distribute them as rewards to EigenLayer operators
 */
contract PaymentContract {
    address public owner;

    // EigenLayer integration
    IServiceManager public serviceManager;
    IERC20 public rewardsToken;

    // Mock WETH for converting ETH to tokens for rewards
    address public mockWETH;

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
        (bool success,) = _to.call{value: balance}("");
        require(success, "Withdraw failed");
    }

    /**
     * @dev Sets the ServiceManager and token addresses for EigenLayer integration
     * @param _serviceManager The address of the EigenLayer ServiceManager
     * @param _rewardsToken The ERC20 token to use for rewards distribution
     * @param _mockWETH Address of the WETH contract (for converting ETH to tokens)
     */
    function setEigenLayerAddresses(address _serviceManager, address _rewardsToken, address _mockWETH) external {
        require(msg.sender == owner, "Only owner can set addresses");
        serviceManager = IServiceManager(_serviceManager);
        rewardsToken = IERC20(_rewardsToken);
        mockWETH = _mockWETH;
    }

    /**
     * @dev Permissionless function to distribute all collected ETH as rewards to operators
     * @notice This is a mock implementation that doesn't actually know which operators to reward
     */
    function distributeRewardsToOperators() external {
        // 1. Get the balance of this contract
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "No ETH to distribute");

        // 2. Convert ETH to tokens (mock implementation)
        // In a real implementation, this would wrap ETH to WETH
        // Here we're just pretending we have tokens
        uint256 tokenAmount = ethBalance;

        // 3. Create rewards submission structure
        IRewardsCoordinator.RewardsSubmission[] memory submissions = new IRewardsCoordinator.RewardsSubmission[](1);

        // 4. Set up strategy parameters (simplified for mock)
        // Define the StrategyAndMultiplier struct inline to match IRewardsCoordinatorTypes
        IRewardsCoordinatorTypes.StrategyAndMultiplier[] memory strategies =
            new IRewardsCoordinatorTypes.StrategyAndMultiplier[](1);

        // 5. Use a mock strategy (this would be a real strategy address in production)
        strategies[0] = IRewardsCoordinatorTypes.StrategyAndMultiplier({
            strategy: IStrategy(address(0x1234)), // Mock strategy address
            multiplier: uint96(10000) // 100% weight to this strategy
        });

        // 6. Configure the submission
        submissions[0] = IRewardsCoordinatorTypes.RewardsSubmission({
            strategiesAndMultipliers: strategies,
            token: rewardsToken,
            amount: tokenAmount,
            startTimestamp: uint32(block.timestamp),
            duration: uint32(7 days) // 1 week duration
        });

        //  Uncomment this in production
        // // 7. Approve tokens for the rewards coordinator
        // rewardsToken.approve(address(serviceManager), tokenAmount);

        // // 8. Submit the rewards to EigenLayer
        // serviceManager.createAVSRewardsSubmission(submissions);

        // 8. For this mock implementation, just send ETH to the owner
        // This simulates the distribution without actually integrating with EigenLayer
        (bool success,) = owner.call{value: ethBalance}("");
        require(success, "ETH transfer failed");

        emit RewardsDistributed(ethBalance, tokenAmount);
    }

    // Event to track rewards distribution
    event RewardsDistributed(uint256 ethAmount, uint256 tokenAmount);
}
