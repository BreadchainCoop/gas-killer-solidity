// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/VotingContract.sol";
import "@eigenlayer-middleware/BLSSignatureChecker.sol";

contract VotingContractTest is Test {
    VotingContract votingContract;

    address public constant BLS_SIG_CHECKER = address(0xCa249215E082E17c12bB3c4881839A3F883e5C6B);

    function setUp() public {
        votingContract = new VotingContract();
    }

    function testAddVoter() public {
        address voter1 = address(0x123);
        address voter2 = address(0x456);
        
        votingContract.addVoter(voter1);
        votingContract.addVoter(voter2);
        
        bytes memory storedVoters = votingContract.getCurrentVotersArray();
        address[] memory decodedVoters = abi.decode(storedVoters, (address[]));
        
        assertEq(decodedVoters.length, 2, "Voter count should be 2");
        assertEq(decodedVoters[0], voter1, "First voter should match");
        assertEq(decodedVoters[1], voter2, "Second voter should match");
    }

    function testGetCurrentTotalVotingPower() public {
        address voter1 = address(0x123);
        address voter2 = address(0x456);
        
        votingContract.addVoter(voter1);
        votingContract.addVoter(voter2);
        uint256 blockNumber = block.number;
        
        uint256 expectedPower = (uint160(voter1) * blockNumber) + (uint160(voter2) * blockNumber);
        uint256 retrievedPower = votingContract.getCurrentTotalVotingPower(blockNumber);
        
        assertEq(retrievedPower, expectedPower, "Total voting power should be correct");
    }

    function testExecuteVoteEvenPower() public {
        address voter1 = address(0x222); // 0x222 is even, so total power should be even
        votingContract.addVoter(voter1);
        
        bool votePassed = votingContract.executeVote();
        assertTrue(votePassed, "Vote should pass when total voting power is even");
    }

    function testExecuteVoteOddPower() public {
        address voter1 = address(0x123); // 0x123 is odd, so total power should be odd
        votingContract.addVoter(voter1);
        
        bool votePassed = votingContract.executeVote();
        assertFalse(votePassed, "Vote should fail when total voting power is odd");
    }

    function testNoVotingPowerBeforeAddingVoters() public {
        uint256 blockNumber = block.number;
        uint256 retrievedPower = votingContract.getCurrentTotalVotingPower(blockNumber);
        
        assertEq(retrievedPower, 0, "Voting power should be zero before adding voters");
    }

    function testOperatorExecuteVoteEven() public {
        // Add a voter whose address, when multiplied by block.number, yields an even total
        // e.g. address(0x222) is even in the low bits.
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        // Capture the current block number after adding the voter
        uint256 blockNumber = block.number;

        // 1) Simulate off-chain aggregator: obtain the storage update payload
        bytes memory storageUpdates = votingContract.operatorExecuteVote(blockNumber);

        // 2) Write these updates on-chain using the test function instead
        votingContract.writeExecuteVoteTest(storageUpdates);

        // 3) Read updated values directly from contract storage
        uint256 finalVotingPower = votingContract.currentTotalVotingPower();
        bool finalVotePassed = votingContract.lastVotePassed();

        // Compute expected voting power for manual check
        uint256 expectedPower = (uint160(voter1) * blockNumber);

        // Check the storage updates worked as intended
        assertEq(finalVotingPower, expectedPower, "Final voting power should match the computed even sum");
        assertTrue(finalVotePassed, "Vote should be considered passed (even voting power)");
    }

    function testOperatorExecuteVoteOdd() public {
        // Add a voter whose address, when multiplied by block.number, yields an odd total
        // e.g. address(0x123).
        address voter1 = address(0x123);
        votingContract.addVoter(voter1);

        uint256 blockNumber = block.number;

        // 1) Simulate off-chain aggregator: obtain the storage update payload
        bytes memory storageUpdates = votingContract.operatorExecuteVote(blockNumber);

        // 2) Write these updates on-chain using the test function
        votingContract.writeExecuteVoteTest(storageUpdates);

        // 3) Read updated values directly from contract storage
        uint256 finalVotingPower = votingContract.currentTotalVotingPower();
        bool finalVotePassed = votingContract.lastVotePassed();

        // Compute expected voting power
        uint256 expectedPower = (uint160(voter1) * blockNumber);

        // Check final results
        assertEq(finalVotingPower, expectedPower, "Final voting power should match the computed odd sum");
        assertFalse(finalVotePassed, "Vote should fail (odd voting power)");
    }

}
