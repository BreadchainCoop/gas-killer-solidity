// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/VotingContract.sol";
import "src/Payments.sol";
import "@eigenlayer-middleware/BLSSignatureChecker.sol";

contract GasBenchmark is Test {
    VotingContract votingContract;
    PaymentContract paymentContract;
    
    // Define constants for benchmarking
    uint256 constant NUM_VOTERS = 200; // Adjust as needed
    address public constant BLS_SIG_CHECKER = address(0xB6861c61782aec28a14cF68cECf216Ad7f5F4e2D);
    address payable testUser = payable(address(0x123));

    function setUp() public {
        // Deploy the contract
        paymentContract = new PaymentContract();
        votingContract = new VotingContract(address(paymentContract));
        
        // Setup test user with sufficient funds
        vm.deal(testUser, 100 ether);
        
        // Add many voters to make the gas costs significant
        for (uint i = 0; i < NUM_VOTERS; i++) {
            // Generate deterministic addresses based on index
            address voter = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            votingContract.addVoter(voter);
        }
        
        console.log("Setup complete with %d voters", NUM_VOTERS);
    }
    
    function _createTestBLSPoints() internal pure returns (
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2, 
        BN254.G1Point memory sigma
    ) {
        // Simple test points
        apk = BN254.G1Point(1, 2);
        
        // Fix: Create uint256[2] arrays explicitly
        uint256[2] memory x = [uint256(5), uint256(6)];
        uint256[2] memory y = [uint256(7), uint256(8)];
        apkG2 = BN254.G2Point(x, y);
        
        sigma = BN254.G1Point(3, 4);
        return (apk, apkG2, sigma);
    }
    
    function testGasComparison() public {
        // Record starting state for reset
        uint256 snapshot = vm.snapshot();
        
        console.log("\n=== Gas Benchmark with %d voters ===", NUM_VOTERS);
        
        // ----------- Benchmark 1: Using off-chain computation + on-chain verification -----------
        
        // 1) Calculate storage updates off-chain (simulated by operatorExecuteVote)
        console.log("\n[Part 1] Using off-chain computation + on-chain verification");
        uint256 transitionIndex = votingContract.stateTransitionCount();
        
        // This would be done off-chain, so we don't measure this gas
        bytes memory updates = votingContract.operatorExecuteVote(transitionIndex);
        
        // 2) Execute on-chain part with gas measurement using the test function
        // that bypasses signature verification
        vm.prank(testUser);
        uint256 gasBefore = gasleft();
        
        // Use writeExecuteVoteTest instead for benchmarking
        (bool success,) = address(votingContract).call{value: 0.1 ether}(
            abi.encodeWithSelector(
                votingContract.writeExecuteVoteTest.selector,
                updates
            )
        );
        
        require(success, "Test execution failed");
        uint256 gasUsedOffchainOnchain = gasBefore - gasleft();
        console.log("Gas used for only on-chain part: %d", gasUsedOffchainOnchain);
        
        // Get final values
        uint256 finalVotingPower1 = votingContract.currentTotalVotingPower();
        bool finalVotePassed1 = votingContract.lastVotePassed();
        // console.log("Final voting power: %d, Vote passed: %s", 
        //     finalVotingPower1, 
        //     finalVotePassed1 ? "true" : "false"
        // );

        // Reset to starting state
        vm.revertTo(snapshot);
        
        // ----------- Benchmark 2: Traditional executeVote (all on-chain) -----------
        console.log("\n[Part 2] Using traditional executeVote (all on-chain)");
        
        // Execute the traditional function with gas measurement
        gasBefore = gasleft();
        bool votePassed = votingContract.executeVote();
        uint256 gasUsedTraditional = gasBefore - gasleft();
        
        console.log("Gas used for traditional executeVote: %d", gasUsedTraditional);
        console.log("Vote passed: %s", votePassed ? "true" : "false");
        
        // ----------- Results -----------
        console.log("\n=== Results ===");
        console.log("Gas used with off-chain + on-chain approach: %d", gasUsedOffchainOnchain);
        console.log("Gas used with traditional all on-chain approach: %d", gasUsedTraditional);
        
        int256 savings = int256(gasUsedTraditional) - int256(gasUsedOffchainOnchain);
        if (savings > 0) {
            console.log("Gas saved: %d (%d%%)", 
                uint256(savings), 
                (uint256(savings) * 100) / gasUsedTraditional
            );
        } else {
            console.log("No gas savings. Traditional used less by: %d", uint256(-savings));
        }
    }
} 