// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/VotingContract.sol";
import "src/Payments.sol";
import "@eigenlayer-middleware/BLSSignatureChecker.sol";

contract VotingContractTest is Test {
    VotingContract votingContract;
    PaymentContract paymentContract;

    address public constant BLS_SIG_CHECKER = address(0xB6861c61782aec28a14cF68cECf216Ad7f5F4e2D);

    // Define a test user with funds for payments
    address payable testUser = payable(address(0x123));

    function setUp() public {
        // Deploy the PaymentContract first
        paymentContract = new PaymentContract();

        // Deploy VotingContract with the PaymentContract address
        votingContract = new VotingContract(address(paymentContract));

        // Give testUser some ETH for payments
        vm.deal(testUser, 10 ether);
    }

    function testAddVoter() public {
        address voter1 = address(0x123);
        address voter2 = address(0x456);

        votingContract.addVoter(voter1);
        votingContract.addVoter(voter2);

        bytes memory storedVoters = votingContract.getCurrentVotersArray();
        address[] memory decodedVoters = abi.decode(storedVoters, (address[]));

        // Now we expect 3 voters: deployer + the 2 we added
        assertEq(decodedVoters.length, 3, "Voter count should be 3");
        // First voter should be the deployer (address(this) in the test)
        assertEq(decodedVoters[0], address(this), "First voter should be the deployer");
        assertEq(decodedVoters[1], voter1, "Second voter should be our first added voter");
        assertEq(decodedVoters[2], voter2, "Third voter should be our second added voter");
    }

    function testGetCurrentTotalVotingPower() public {
        address voter1 = address(0x123);
        address voter2 = address(0x456);

        votingContract.addVoter(voter1);
        votingContract.addVoter(voter2);

        // Use the current transition count
        uint256 transitionIndex = votingContract.stateTransitionCount();

        // Calculate with transition index instead of block number
        uint256 expectedPower = (uint160(address(this)) * transitionIndex) + (uint160(voter1) * transitionIndex)
            + (uint160(voter2) * transitionIndex);

        uint256 retrievedPower = votingContract.getCurrentTotalVotingPower(transitionIndex);

        assertEq(retrievedPower, expectedPower, "Total voting power should be correct");
    }

    function testExecuteVoteEvenPower() public {
        address voter1 = address(0x222); // 0x222 is even, so total power should be even
        votingContract.addVoter(voter1);

        bool votePassed = votingContract.executeVote();
        assertTrue(votePassed, "Vote should pass when total voting power is even");
    }

    function testExecuteVoteOddPower() public {
        // Add a voter with specific address to test voting power
        address voter1 = address(0x123);
        votingContract.addVoter(voter1);

        // Get the transition index BEFORE executing vote
        uint256 preExecuteTransition = votingContract.stateTransitionCount();

        // Execute the vote - this will increase the transition count due to trackState modifier
        bool votePassed = votingContract.executeVote();

        // Get the NEW transition index AFTER executing vote
        uint256 postExecuteTransition = votingContract.stateTransitionCount();

        // Verify the transition count increased
        assertEq(postExecuteTransition, preExecuteTransition + 1, "Transition count should increase by 1");

        // Calculate the voting power with the NEW transition index that executeVote() used
        uint256 votingPower = votingContract.getCurrentTotalVotingPower(postExecuteTransition);
        bool isVotingPowerEven = votingPower % 2 == 0;

        // Now check against the correct transition index
        assertEq(votePassed, isVotingPowerEven, "Vote should pass if voting power at new transition is even");
    }

    function testNoVotingPowerBeforeAddingVoters() public {
        uint256 blockNumber = block.number;
        uint256 retrievedPower = votingContract.getCurrentTotalVotingPower(blockNumber);

        // We now expect the deployer's voting power
        uint256 expectedPower = uint160(address(this)) * blockNumber;

        assertEq(retrievedPower, expectedPower, "Voting power should include deployer's power");
    }

    function testOperatorExecuteVoteEven() public {
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        uint256 transitionIndex = votingContract.stateTransitionCount();
        bytes memory storageUpdates = votingContract.operatorExecuteVote(transitionIndex);

        vm.prank(testUser);
        (bool success,) = address(votingContract).call{value: 0.0001 ether}(
            abi.encodeWithSelector(votingContract.writeExecuteVoteTest.selector, storageUpdates)
        );
        require(success, "Call failed");

        uint256 finalVotingPower = votingContract.currentTotalVotingPower();
        bool votePassed = votingContract.lastVotePassed();

        // Calculate the expected voting power with transitionIndex + 1 since we changed that in operatorExecuteVote
        uint256 expectedVotingPower =
            (uint160(address(this)) * (transitionIndex + 1)) + (uint160(voter1) * (transitionIndex + 1));

        assertEq(finalVotingPower, expectedVotingPower, "Final voting power should match the computed value");
        assertTrue(votePassed, "Vote should pass with even voting power");
    }

    function testOperatorExecuteVoteOdd() public {
        address voter1 = address(0x123);
        votingContract.addVoter(voter1);

        uint256 transitionIndex = votingContract.stateTransitionCount();
        bytes memory storageUpdates = votingContract.operatorExecuteVote(transitionIndex);

        vm.prank(testUser);
        (bool success,) = address(votingContract).call{value: 0.0001 ether}(
            abi.encodeWithSelector(votingContract.writeExecuteVoteTest.selector, storageUpdates)
        );
        require(success, "Call failed");

        uint256 finalVotingPower = votingContract.currentTotalVotingPower();
        bool votePassed = votingContract.lastVotePassed();

        // Calculate the expected voting power with transitionIndex + 1
        uint256 expectedVotingPower =
            (uint160(address(this)) * (transitionIndex + 1)) + (uint160(voter1) * (transitionIndex + 1));

        assertEq(finalVotingPower, expectedVotingPower, "Final voting power should match the computed odd sum");
        assertFalse(votePassed, "Vote should not pass with odd voting power");
    }

    // Helper function to generate a mock signature for testing
    function _generateMockSignature(
        uint256 blockNumber,
        address targetAddr,
        bytes4 targetFunction,
        bytes memory storageUpdates
    ) internal pure returns (bytes memory) {
        // Hardcoded namespace matching the contract
        bytes memory namespace = "_COMMONWARE_AGGREGATION_";

        // Hash all parameters in specified order to create the message hash
        bytes32 hash = sha256(abi.encodePacked(namespace, blockNumber, targetAddr, targetFunction, storageUpdates));

        // Return the hash as a bytes array (simulating a signature)
        return abi.encodePacked(hash);
    }

    // Helper function to create a more suitable mock NonSignerStakesAndSignature struct
    function _createMockNonSignerStakesAndSignature()
        internal
        pure
        returns (BLSSignatureChecker.NonSignerStakesAndSignature memory)
    {
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

    // Test that slashing is needed for valid signature
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

        bytes4 targetFunction = bytes4(
            keccak256(
                "writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"
            )
        );

        // Generate a valid mock signature hash
        bytes32 validMsgHash = sha256(
            abi.encodePacked(
                votingContract.namespace(), blockNumber, address(votingContract), targetFunction, correctUpdates
            )
        );

        // Mock the BLS verification to succeed
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector, validMsgHash, apk, apkG2, sigma
            ),
            abi.encode(true, true) // Returns (pairingSuccessful, signatureIsValid) = (true, true)
        );

        // Call slashExecVote with valid parameters
        bytes memory result = votingContract.slashExecVote(
            validMsgHash, apk, apkG2, sigma, correctUpdates, blockNumber, address(votingContract), targetFunction
        );

        // Decode the result
        bool slashNeeded = abi.decode(result, (bool));

        // Verify no slashing is needed
        assertFalse(slashNeeded, "Slashing should not be needed for valid parameters");
    }

    // Test that slashing is needed for invalid signature
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

        bytes4 targetFunction = bytes4(
            keccak256(
                "writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"
            )
        );

        // Generate an invalid message hash (using a different target address)
        bytes32 invalidMsgHash = sha256(
            abi.encodePacked(
                votingContract.namespace(),
                blockNumber,
                address(0x999), // Different address
                targetFunction,
                correctUpdates
            )
        );

        // Mock the BLS verification to fail for invalid signature
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector, invalidMsgHash, apk, apkG2, sigma
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

        bytes4 targetFunction = bytes4(
            sha256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)")
        );

        // Generate a valid message hash
        bytes32 validMsgHash = sha256(
            abi.encodePacked(
                votingContract.namespace(), blockNumber, address(votingContract), targetFunction, correctUpdates
            )
        );

        // Mock the BLS verification to fail with pairing failure
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector, validMsgHash, apk, apkG2, sigma
            ),
            abi.encode(false, false) // Returns (pairingSuccessful, signatureIsValid) = (false, false)
        );

        // Call slashExecVote with valid hash but pairing failure
        bytes memory result = votingContract.slashExecVote(
            validMsgHash, apk, apkG2, sigma, correctUpdates, blockNumber, address(votingContract), targetFunction
        );

        // Decode the result
        bool slashNeeded = abi.decode(result, (bool));

        // Verify slashing is needed because pairing failed
        assertTrue(slashNeeded, "Slashing should be needed for pairing failure");
    }

    // Helper function to create BLS points for testing
    function _createTestBLSPoints()
        internal
        pure
        returns (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma)
    {
        // Create simple test values for BLS points
        apk = BN254.G1Point(1, 2);

        uint256[2] memory x = [uint256(5), uint256(6)];
        uint256[2] memory y = [uint256(7), uint256(8)];
        apkG2 = BN254.G2Point(x, y);

        sigma = BN254.G1Point(3, 4);

        return (apk, apkG2, sigma);
    }

    // Helper function to simplify test payment execution
    function _executeTestPayment() internal {
        // Add a voter to have some state
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        // Get the current transition index
        uint256 transitionIndex = votingContract.stateTransitionCount();

        // Get the storage updates
        bytes memory updates = votingContract.operatorExecuteVote(transitionIndex);

        // Use the test method that doesn't require verification
        vm.prank(testUser);
        (bool success,) = address(votingContract).call{value: 0.0001 ether}(
            abi.encodeWithSelector(votingContract.writeExecuteVoteTest.selector, updates)
        );
        require(success, "Call failed");
    }

    // Test that non-owner cannot withdraw
    function testCannotWithdrawAsNonOwner() public {
        // Check initial balance
        assertEq(address(paymentContract).balance, 0, "Payment contract should start with 0 balance");

        // Execute a payment to have some funds in the contract
        _executeTestPayment();

        // Verify funds were sent
        assertEq(address(paymentContract).balance, 0.0001 ether, "Payment contract should have 0.0001 ETH");

        // Setup a receiver address
        address payable receiver = payable(address(0x789));

        // Try to withdraw as non-owner (using testUser which is not the owner)
        vm.expectRevert("Only owner can withdraw");
        vm.prank(testUser);
        paymentContract.withdraw(receiver);
    }

    // Test that the function works correctly with valid parameters
    function testPaymentContractWithdrawal() public {
        // Check initial balance
        assertEq(address(paymentContract).balance, 0, "Payment contract should start with 0 balance");

        // Execute a payment to have some funds in the contract
        _executeTestPayment();

        // Verify funds were sent
        assertEq(address(paymentContract).balance, 0.0001 ether, "Payment contract should have 0.0001 ETH");

        // Get initial balance of receiver
        address payable receiver = payable(address(0x789));
        uint256 initialBalance = receiver.balance;

        // Withdraw as the owner (the test contract)
        paymentContract.withdraw(receiver);

        // Check balances after withdrawal
        assertEq(address(paymentContract).balance, 0, "Payment contract should have 0 ETH after withdrawal");
        assertEq(receiver.balance, initialBalance + 0.0001 ether, "Receiver should have received 0.0001 ETH");
    }

    // Test that the function works correctly with valid parameters
    function testWriteExecuteVote() public {
        // Verify starting balance
        assertEq(address(paymentContract).balance, 0, "Payment contract should start with 0 balance");

        // Add a mock voter (address that makes voting power even)
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        // Get the current transition index
        uint256 transitionIndex = votingContract.stateTransitionCount();

        // Get the storage updates from the operator function
        bytes memory storageUpdates = votingContract.operatorExecuteVote(transitionIndex);

        // Use the test method that doesn't require verification
        vm.prank(testUser);
        (bool success,) = address(votingContract).call{value: 0.0001 ether}(
            abi.encodeWithSelector(votingContract.writeExecuteVoteTest.selector, storageUpdates)
        );
        require(success, "Call failed");

        // Verify funds were sent
        assertEq(address(paymentContract).balance, 0.0001 ether, "Payment contract should have 0.0001 ETH");

        // Verify state was updated
        uint256 votingPower = votingContract.currentTotalVotingPower();

        // Calculate the expected voting power with transitionIndex + 1
        uint256 expectedVotingPower =
            (uint160(address(this)) * (transitionIndex + 1)) + (uint160(voter1) * (transitionIndex + 1));

        assertEq(votingPower, expectedVotingPower, "Total voting power should be updated correctly");
        assertTrue(votingContract.lastVotePassed(), "Vote should have passed with even voting power");
    }

    // Test that the function reverts if the wrong amount of ETH is sent
    function testWriteExecuteVoteMustSendExactAmount() public {
        // Add a voter to have some state
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        // Get the current block number
        uint256 blockNumber = block.number;

        // Get the storage updates
        bytes memory updates = votingContract.operatorExecuteVote(blockNumber);

        // Get test BLS points
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();

        bytes4 targetFunction = bytes4(
            sha256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)")
        );

        // Generate a valid message hash
        bytes32 validMsgHash = sha256(
            abi.encodePacked(votingContract.namespace(), blockNumber, address(votingContract), targetFunction, updates)
        );

        // Mock the BLS verification to succeed
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector, validMsgHash, apk, apkG2, sigma
            ),
            abi.encode(true, true)
        );

        // Try to call with too little ETH and expect revert
        vm.prank(testUser);
        (bool success,) = address(votingContract).call{value: 0.05 ether}(
            abi.encodeWithSelector(
                votingContract.writeExecuteVote.selector,
                validMsgHash,
                apk,
                apkG2,
                sigma,
                updates,
                blockNumber,
                address(votingContract),
                targetFunction
            )
        );
        assertFalse(success, "Call should fail with incorrect ETH amount");
    }

    // Test that a front-run in the same block reverts
    function testFrontRunSameBlockReverts() public {
        //  Add a voter so we move to transitionIndex = 2
        //    (initial deploy = 1, first addVoter = 2)
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        // Get the current transition index
        uint256 staleTransitionIndex = votingContract.stateTransitionCount();
        bytes memory staleUpdates = votingContract.operatorExecuteVote(staleTransitionIndex);

        // Get test BLS points
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();
        bytes4 targetFunction = bytes4(
            keccak256(
                "writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"
            )
        );

        // This is the hash for transitionIndex = 2
        bytes32 msgHashStale = sha256(
            abi.encodePacked(
                votingContract.namespace(), staleTransitionIndex, address(votingContract), targetFunction, staleUpdates
            )
        );

        // Mock the BLS check to succeed for that stale hash
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector, msgHashStale, apk, apkG2, sigma
            ),
            abi.encode(true, true)
        );

        // 4) Now, a front-run TX occurs in the *same block* that changes state again.
        //    We do *another* addVoter, which increments the transition index => 3.
        //    We'll forcibly revert the block number afterward, to simulate them being
        //    in the same block.
        uint256 oldBlock = block.number;
        address voter2 = address(0x333);
        votingContract.addVoter(voter2);
        // Force the block number back so the next call is in the "same block"
        vm.roll(oldBlock);

        // The contract's real transition index is now 3. But aggregator is about to
        // call writeExecuteVote using transition index = 2. This no longer matches
        // the contract's newly updated state. The signature we computed is stale.

        // 5) Attempt the aggregator's write with the stale signature + updates
        vm.deal(testUser, 10 ether);
        vm.prank(testUser);

        // Expect revert with InvalidTransitionIndex error
        vm.expectRevert(VotingContract.InvalidTransitionIndex.selector);

        // transitionIndex is stale, so the call will revert
        (bool success, bytes memory data) = address(votingContract).call{value: 0.0001 ether}(
            abi.encodeWithSelector(
                votingContract.writeExecuteVote.selector,
                msgHashStale,
                apk,
                apkG2,
                sigma,
                staleUpdates,
                staleTransitionIndex,
                address(votingContract),
                targetFunction
            )
        );

        // Check that it reverted for right reason. should be sucess if cause of revert is InvalidTransitionIndex
        // manually adding staleTransitionIndex+1 to the call makes this fail because the revert reason becomes invalid signature
        assertTrue(success, "Call should have reverted due to stale signature");
    }
}
