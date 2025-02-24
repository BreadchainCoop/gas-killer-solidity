// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/VotingContract.sol";

contract VotingContractTest is Test {
    VotingContract votingContract;

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
}
