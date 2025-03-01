// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "src/VotingContract.sol";
import "src/Payments.sol";

/**
 * @title BenchmarkComparison
 * @notice This script deploys two voting contracts and compares gas costs
 *         between traditional voting and optimized off-chain computation
 */
contract BenchmarkComparison is Script {
    // Number of voters to add
    uint256 constant NUM_VOTERS = 40;
    // Number of votes to execute
    uint256 constant NUM_VOTES = 1;

    // The contracts we'll deploy
    VotingContract traditionalVoting;
    VotingContract optimizedVoting;
    PaymentContract paymentContract;

    // Track total gas used
    uint256 totalGasTraditional;
    uint256 totalGasOptimized;

    function setUp() public {}

    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy payment contract
        paymentContract = new PaymentContract();

        // Deploy both voting contracts
        traditionalVoting = new VotingContract(address(paymentContract));
        optimizedVoting = new VotingContract(address(paymentContract));

        console.log("Contracts deployed:");
        console.log("- Payment Contract: %s", address(paymentContract));
        console.log("- Traditional Voting: %s", address(traditionalVoting));
        console.log("- Optimized Voting: %s", address(optimizedVoting));

        // Generate voter addresses in advance
        address[] memory voters = new address[](NUM_VOTERS);
        for (uint256 i = 0; i < NUM_VOTERS; i++) {
            voters[i] = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
        }

        // For parallelization, we'll add voters using concurrent transactions
        // This uses multiple transaction submissions in a single broadcast session
        console.log("Adding %d voters to contracts...", NUM_VOTERS);

        // First add voters to traditional voting contract
        for (uint256 i = 0; i < NUM_VOTERS; i++) {
            // These transactions will be submitted together in a concurrent manner
            // within the same broadcast session
            traditionalVoting.addVoter(voters[i]);

            // Log progress occasionally to avoid excessive console output
            if (i % 10 == 0) {
                console.log("Added %d/%d voters to traditional contract", i, NUM_VOTERS);
            }
        }

        // Then add voters to optimized voting contract
        for (uint256 i = 0; i < NUM_VOTERS; i++) {
            optimizedVoting.addVoter(voters[i]);

            if (i % 10 == 0) {
                console.log("Added %d/%d voters to optimized contract", i, NUM_VOTERS);
            }
        }

        console.log("Added all voters to both contracts");

        // Execute votes and measure gas
        console.log("\n=== Starting Benchmark ===");
        console.log("Executing %d votes on each contract...", NUM_VOTES);

        // Benchmark traditional voting
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < NUM_VOTES; i++) {
            traditionalVoting.executeVote();
        }
        totalGasTraditional = gasBefore - gasleft();

        // Pre-compute all the updates off-chain (simulated)
        bytes[] memory allUpdates = new bytes[](NUM_VOTES);
        for (uint256 i = 0; i < NUM_VOTES; i++) {
            // Get transition index - this would be known off-chain
            uint256 transitionIndex = optimizedVoting.stateTransitionCount() + i;

            // Get storage updates - this would be done off-chain
            allUpdates[i] = optimizedVoting.operatorExecuteVote(transitionIndex);
        }

        // Now benchmark only the on-chain part of the optimized approach
        gasBefore = gasleft();
        for (uint256 i = 0; i < NUM_VOTES; i++) {
            // Apply updates on-chain - this is the only part we should measure
            optimizedVoting.writeExecuteVoteTest{value: 0.0001 ether}(allUpdates[i]);
        }
        totalGasOptimized = gasBefore - gasleft();

        // Report results
        console.log("\n=== Results ===");
        console.log("Traditional voting total gas: %d", totalGasTraditional);
        console.log("Optimized voting total gas: %d", totalGasOptimized);

        if (totalGasTraditional > totalGasOptimized) {
            uint256 savings = totalGasTraditional - totalGasOptimized;
            uint256 savingsPercent = (savings * 100) / totalGasTraditional;
            console.log("Gas saved: %d (%d%%)", savings, savingsPercent);
        } else {
            uint256 increase = totalGasOptimized - totalGasTraditional;
            uint256 increasePercent = (increase * 100) / totalGasTraditional;
            console.log("Gas increased: %d (%d%%)", increase, increasePercent);
        }

        console.log("Average gas per vote (traditional): %d", totalGasTraditional / NUM_VOTES);
        console.log("Average gas per vote (optimized): %d", totalGasOptimized / NUM_VOTES);

        // Stop broadcasting
        vm.stopBroadcast();
    }
}
