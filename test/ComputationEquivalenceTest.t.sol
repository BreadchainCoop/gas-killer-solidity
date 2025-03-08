// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/VotingContract.sol";
import "src/Payments.sol";

/**
 * This test verifies that both voting methods (traditional and storage-updates)
 * produce identical results for the same starting state.
 */
contract ComputationEquivalenceTest is Test {
    VotingContract votingContract;
    PaymentContract paymentContract;

    // Define constants for testing
    uint256 constant NUM_VOTERS = 50; // Lower for faster testing
    address payable testUser = payable(address(0x123));

    function setUp() public {
        // Deploy the contract
        paymentContract = new PaymentContract();
        votingContract = new VotingContract(address(paymentContract));

        // Setup test user with sufficient funds
        vm.deal(testUser, 10 ether);

        // Add some voters in a deterministic way
        for (uint256 i = 0; i < NUM_VOTERS; i++) {
            address voter = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            votingContract.addVoter(voter);
        }

        console.log("Setup complete with %d voters", NUM_VOTERS);
    }

    function testComputationalEquivalence() public {
        // We'll run multiple scenarios with different starting states
        // to ensure robust verification

        for (uint256 scenario = 1; scenario <= 5; scenario++) {
            console.log("\n=== Testing Scenario %d ===", scenario);

            // Create a unique state for this scenario by adding a specific voter
            address specialVoter = address(uint160(uint256(keccak256(abi.encodePacked("scenario", scenario)))));
            votingContract.addVoter(specialVoter);

            // Take a snapshot of this state
            uint256 snapshot = vm.snapshot();

            // --- Method 1: Traditional executeVote ---
            bool traditionalVotePassed = votingContract.executeVote();
            uint256 traditionalVotingPower = votingContract.currentTotalVotingPower();

            console.log("Traditional method results:");
            console.log("  - Voting power: %d", traditionalVotingPower);
            console.log("  - Vote passed: %s", traditionalVotePassed ? "true" : "false");

            // Revert to snapshot to ensure identical starting state
            vm.revertTo(snapshot);

            // --- Method 2: Off-chain computation + on-chain application ---
            // Get the current transition index
            uint256 transitionIndex = votingContract.stateTransitionCount();

            // This would be done off-chain, simulated here
            bytes memory updates = votingContract.operatorExecuteVote(transitionIndex);

            // Apply the updates on-chain
            vm.prank(testUser);
            (bool success,) = address(votingContract).call{value: 0.0001 ether}(
                abi.encodeWithSelector(votingContract.writeExecuteVoteTest.selector, updates)
            );
            require(success, "Test execution failed");

            // Get the results
            uint256 optimizedVotingPower = votingContract.currentTotalVotingPower();
            bool optimizedVotePassed = votingContract.lastVotePassed();

            console.log("Optimized method results:");
            console.log("  - Voting power: %d", optimizedVotingPower);
            console.log("  - Vote passed: %s", optimizedVotePassed ? "true" : "false");

            // --- Verify equivalence ---
            assertEq(traditionalVotingPower, optimizedVotingPower, "Voting power should be identical between methods");

            assertEq(traditionalVotePassed, optimizedVotePassed, "Vote outcome should be identical between methods");

            console.log("Methods produced identical results");

            // Take another snapshot before the next scenario
            snapshot = vm.snapshot();
        }

        console.log("\n All scenarios verified - methods are computationally equivalent");
    }
}
