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
        // Add a voter whose address, when multiplied by block.number, yields an odd total
        address voter1 = address(0x123);
        votingContract.addVoter(voter1);
        
        // Make sure the block number is odd to ensure odd voting power
        vm.roll(block.number | 1); // Force odd block number
        
        bool votePassed = votingContract.executeVote();
        
        // Verify the voting power is actually odd
        uint256 votingPower = votingContract.getCurrentTotalVotingPower(block.number);
        assertTrue(votingPower % 2 == 1, "Total voting power should be odd");
        
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

        // Make sure the block number is odd to ensure odd voting power
        vm.roll(block.number | 1); // Force odd block number
        
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
        
        // Verify the voting power is actually odd
        assertTrue(expectedPower % 2 == 1, "Expected voting power should be odd");

        // Check final results
        assertEq(finalVotingPower, expectedPower, "Final voting power should match the computed odd sum");
        assertFalse(finalVotePassed, "Vote should fail (odd voting power)");
    }

    /**
     * @notice Helper function to generate a mock signature for testing
     * @dev Creates a signature by hashing the parameters in the correct order
     */
    function _generateMockSignature(
        uint256 blockNumber,
        address targetAddr,
        bytes4 targetFunction,
        bytes memory storageUpdates
    ) internal pure returns (bytes memory) {
        // Hardcoded namespace matching the contract
        bytes memory namespace = "_COMMONWARE_AGGREGATION_";
        
        // Hash all parameters in specified order to create the message hash
        bytes32 hash = keccak256(abi.encodePacked(
            namespace,
            blockNumber,
            targetAddr,
            targetFunction,
            storageUpdates
        ));
        
        // Return the hash as a bytes array (simulating a signature)
        return abi.encodePacked(hash);
    }

    // Updated helper function to create a more suitable mock NonSignerStakesAndSignature struct
    function _createMockNonSignerStakesAndSignature() internal pure returns (BLSSignatureChecker.NonSignerStakesAndSignature memory) {
        BLSSignatureChecker.NonSignerStakesAndSignature memory params;
        
        // Initialize with a properly sized array for quorumApks - we need at least one element
        params.quorumApks = new BN254.G1Point[](1);
        params.quorumApks[0] = BN254.G1Point(1, 2); // Simple non-zero values
        
        // Mock G1Point for sigma (signature)
        params.sigma = BN254.G1Point(3, 4); // Simple non-zero values for testing
        
        // Initialize the G2Point for apkG2
        uint256[2] memory x = [uint256(5), uint256(6)];
        uint256[2] memory y = [uint256(7), uint256(8)];
        params.apkG2 = BN254.G2Point(x, y);
        
        // Initialize the rest of the arrays that we're not using with the new function
        params.nonSignerPubkeys = new BN254.G1Point[](0);
        params.quorumApkIndices = new uint32[](1);
        params.quorumApkIndices[0] = 0;
        params.nonSignerQuorumBitmapIndices = new uint32[](0);
        params.totalStakeIndices = new uint32[](1);
        params.totalStakeIndices[0] = 0;
        params.nonSignerStakeIndices = new uint32[][](0);
        
        return params;
    }

    function testSlashExecVoteValid() public {
        // Add a voter to have some state
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);
        
        // Get the current block number
        uint256 blockNumber = block.number;
        
        // Get the correct storage updates
        bytes memory correctUpdates = votingContract.operatorExecuteVote(blockNumber);
        
        // Get test BLS points
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();
        
        bytes4 targetFunction = bytes4(keccak256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"));
        
        // Generate a valid mock signature hash
        bytes32 validMsgHash = keccak256(abi.encodePacked(
            votingContract.namespace(),
            blockNumber,
            address(votingContract),
            targetFunction,
            correctUpdates
        ));
        
        // Mock the BLS verification to succeed
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector,
                validMsgHash,
                apk,
                apkG2,
                sigma
            ),
            abi.encode(true, true) // Returns (pairingSuccessful, signatureIsValid) = (true, true)
        );
        
        // Call slashExecVote with valid parameters
        bytes memory result = votingContract.slashExecVote(
            validMsgHash,
            apk,
            apkG2,
            sigma,
            correctUpdates,
            blockNumber,
            address(votingContract),
            targetFunction
        );
        
        // Decode the result
        bool slashNeeded = abi.decode(result, (bool));
        
        // Verify no slashing is needed
        assertFalse(slashNeeded, "Slashing should not be needed for valid parameters");
    }

    function testSlashExecVoteInvalidSignature() public {
        // Add a voter to have some state
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);
        
        // Get the current block number
        uint256 blockNumber = block.number;
        
        // Get the correct storage updates
        bytes memory correctUpdates = votingContract.operatorExecuteVote(blockNumber);
        
        // Get test BLS points
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();
        
        bytes4 targetFunction = bytes4(keccak256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"));
        
        // Generate an invalid message hash (using a different target address)
        bytes32 invalidMsgHash = keccak256(abi.encodePacked(
            votingContract.namespace(),
            blockNumber,
            address(0x999), // Different address
            targetFunction,
            correctUpdates
        ));
        
        // Mock the BLS verification to fail for invalid signature
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector,
                invalidMsgHash,
                apk,
                apkG2,
                sigma
            ),
            abi.encode(true, false) // Returns (pairingSuccessful, signatureIsValid) = (true, false)
        );
        
        // Call slashExecVote with invalid signature but correct updates
        bytes memory result = votingContract.slashExecVote(
            invalidMsgHash,
            apk,
            apkG2,
            sigma,
            correctUpdates,
            blockNumber,
            address(votingContract), // Correct address in the call
            targetFunction
        );
        
        // Decode the result
        bool slashNeeded = abi.decode(result, (bool));
        
        // Verify slashing is needed because signature is invalid
        assertTrue(slashNeeded, "Slashing should be needed for invalid signature");
    }

    // Add a test for pairing failure
    function testSlashExecVotePairingFailure() public {
        // Add a voter to have some state
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);
        
        // Get the current block number
        uint256 blockNumber = block.number;
        
        // Get the correct storage updates
        bytes memory correctUpdates = votingContract.operatorExecuteVote(blockNumber);
        
        // Get test BLS points
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();
        
        bytes4 targetFunction = bytes4(keccak256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"));
        
        // Generate a valid message hash
        bytes32 validMsgHash = keccak256(abi.encodePacked(
            votingContract.namespace(),
            blockNumber,
            address(votingContract),
            targetFunction,
            correctUpdates
        ));
        
        // Mock the BLS verification to fail with pairing failure
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector,
                validMsgHash,
                apk,
                apkG2,
                sigma
            ),
            abi.encode(false, false) // Returns (pairingSuccessful, signatureIsValid) = (false, false)
        );
        
        // Call slashExecVote with valid hash but pairing failure
        bytes memory result = votingContract.slashExecVote(
            validMsgHash,
            apk,
            apkG2,
            sigma,
            correctUpdates,
            blockNumber,
            address(votingContract),
            targetFunction
        );
        
        // Decode the result
        bool slashNeeded = abi.decode(result, (bool));
        
        // Verify slashing is needed because pairing failed
        assertTrue(slashNeeded, "Slashing should be needed for pairing failure");
    }

    // Helper function to create BLS points for testing
    function _createTestBLSPoints() internal pure returns (
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory sigma
    ) {
        // Create simple test values for BLS points
        apk = BN254.G1Point(1, 2);
        
        uint256[2] memory x = [uint256(5), uint256(6)];
        uint256[2] memory y = [uint256(7), uint256(8)];
        apkG2 = BN254.G2Point(x, y);
        
        sigma = BN254.G1Point(3, 4);
        
        return (apk, apkG2, sigma);
    }

    function testWriteExecuteVote() public {
        // Add a voter to have some state
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);
        
        // Get the current block number
        uint256 blockNumber = block.number;
        
        // Get the storage updates
        bytes memory updates = votingContract.operatorExecuteVote(blockNumber);
        
        // Get test BLS points
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();
        
        bytes4 targetFunction = bytes4(keccak256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"));
        
        // Generate a valid message hash
        bytes32 validMsgHash = keccak256(abi.encodePacked(
            votingContract.namespace(),
            blockNumber,
            address(votingContract),
            targetFunction,
            updates
        ));
        
        // Mock the BLS verification to succeed
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector,
                validMsgHash,
                apk,
                apkG2,
                sigma
            ),
            abi.encode(true, true) // Returns (pairingSuccessful, signatureIsValid) = (true, true)
        );
        
        // Call writeExecuteVote with the test data
        bytes memory result = votingContract.writeExecuteVote(
            validMsgHash,
            apk,
            apkG2,
            sigma,
            updates,
            blockNumber,
            address(votingContract),
            targetFunction
        );
        
        // Decode and verify the result
        (uint256 totalVotingPower, bool votePassed) = abi.decode(result, (uint256, bool));
        
        // Compute expected power
        uint256 expectedPower = uint160(voter1) * blockNumber;
        
        // Verify results
        assertEq(totalVotingPower, expectedPower, "Total voting power should be updated correctly");
        assertEq(votePassed, expectedPower % 2 == 0, "Vote result should be correct");
    }

}
