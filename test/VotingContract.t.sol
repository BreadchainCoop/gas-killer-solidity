// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/VotingContract.sol";
import "src/Payments.sol";
import "@eigenlayer-middleware/BLSSignatureChecker.sol";

contract VotingContractTest is Test {
    VotingContract votingContract;
    PaymentContract paymentContract;

    address public constant BLS_SIG_CHECKER = address(0xCa249215E082E17c12bB3c4881839A3F883e5C6B);
    
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
        uint256 expectedPower = (uint160(address(this)) * transitionIndex) + 
                               (uint160(voter1) * transitionIndex) + 
                               (uint160(voter2) * transitionIndex);
                           
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
        
        // Log values for clarity
        console.log("Pre-execute Transition:", preExecuteTransition);
        console.log("Post-execute Transition:", postExecuteTransition);
        console.log("Voting Power at post-execute transition:", votingPower);
        console.log("Is this power even?", isVotingPowerEven);
        console.log("Vote Passed:", votePassed);
        
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
        // Add a voter whose address, when multiplied by transition index, yields an even total
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        // Get the current state transition index after adding the voter
        uint256 transitionIndex = votingContract.stateTransitionCount();

        // 1) Simulate off-chain aggregator: obtain the storage update payload
        bytes memory storageUpdates = votingContract.operatorExecuteVote(transitionIndex);

        // 2) Call the test function as testUser and send required ETH
        vm.prank(testUser);
        (bool success,) = address(votingContract).call{value: 0.1 ether}(
            abi.encodeWithSelector(
                votingContract.writeExecuteVoteTest.selector,
                storageUpdates
            )
        );
        require(success, "Call failed");

        // 3) Read updated values directly from contract storage
        uint256 finalVotingPower = votingContract.currentTotalVotingPower();
        bool finalVotePassed = votingContract.lastVotePassed();

        // Compute expected voting power with the transition index
        uint256 expectedPower = (uint160(address(this)) * transitionIndex) + (uint160(voter1) * transitionIndex);

        // Check the storage updates worked as intended
        assertEq(finalVotingPower, expectedPower, "Final voting power should match the computed value");
        assertEq(finalVotePassed, expectedPower % 2 == 0, "Vote result should match expected");
    }

    function testOperatorExecuteVoteOdd() public {
        // Add a voter whose address, when multiplied by transition index, yields an odd sum
        address voter1 = address(0x123);
        votingContract.addVoter(voter1);

        // Get the current state transition index after adding the voter
        uint256 transitionIndex = votingContract.stateTransitionCount();

        // 1) Simulate off-chain aggregator: obtain the storage update payload
        bytes memory storageUpdates = votingContract.operatorExecuteVote(transitionIndex);

        // 2) Call the test function as testUser and send required ETH
        vm.prank(testUser);
        (bool success,) = address(votingContract).call{value: 0.1 ether}(
            abi.encodeWithSelector(
                votingContract.writeExecuteVoteTest.selector,
                storageUpdates
            )
        );
        require(success, "Call failed");

        // 3) Read updated values directly from contract storage
        uint256 finalVotingPower = votingContract.currentTotalVotingPower();
        bool finalVotePassed = votingContract.lastVotePassed();

        // Compute expected voting power with the transition index
        uint256 expectedPower = (uint160(address(this)) * transitionIndex) + (uint160(voter1) * transitionIndex);

        // Check the storage updates worked as intended
        assertEq(finalVotingPower, expectedPower, "Final voting power should match the computed odd sum");
        assertEq(finalVotePassed, expectedPower % 2 == 0, "Vote result should match expected");
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
        bytes32 hash = sha256(abi.encodePacked(
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
        bytes32 validMsgHash = sha256(abi.encodePacked(
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
        bytes32 invalidMsgHash = sha256(abi.encodePacked(
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
        
        bytes4 targetFunction = bytes4(sha256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"));
        
        // Generate a valid message hash
        bytes32 validMsgHash = sha256(abi.encodePacked(
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

    // Updated helper function to send a payment (shared logic for multiple tests)
    function _executePayment() internal {
        // Add a voter to have some state
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        // Get the current block number before advancing
        uint256 currentBlock = block.number;
        
        // Move to next block to ensure state transition
        vm.roll(currentBlock + 1);
        
        // Get the current transition index
        uint256 transitionIndex = votingContract.stateTransitionCount();
        
        // Get the storage updates with the transition index
        bytes memory updates = votingContract.operatorExecuteVote(transitionIndex);
        
        // Get test BLS points
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();
        
        bytes4 targetFunction = bytes4(sha256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"));
        
        // Generate a valid message hash using transition index
        bytes32 validMsgHash = sha256(abi.encodePacked(
            votingContract.namespace(),
            transitionIndex,
            address(votingContract),
            targetFunction,
            updates
        ));

        // Mock the BLS verification
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector,
                validMsgHash,
                apk,
                apkG2,
                sigma
            ),
            abi.encode(true, true)
        );

        // Make sure testUser has enough ETH
        vm.deal(testUser, 10 ether);

        // Call writeExecuteVote with transition index
        vm.prank(testUser);
        
        // Get current transition index and log it
        uint256 currentTransition = votingContract.stateTransitionCount();
        console.log("Current transition index:", currentTransition);
        console.log("Transition index being used:", transitionIndex);
        
        (bool success, ) = address(votingContract).call{value: 0.1 ether}(
            abi.encodeWithSelector(
                votingContract.writeExecuteVote.selector,
                validMsgHash,
                apk,
                apkG2,
                sigma,
                updates,
                transitionIndex,
                address(votingContract),
                targetFunction
            )
        );
        require(success, "Call failed");
    }

    // Updated tests to use the helper function
    function testWriteExecuteVote() public {
        // Make sure we start with a clean state
        assertEq(address(paymentContract).balance, 0, "Payment contract should start with 0 balance");
        
        // Add a voter to have some state
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);
        
        // Get the current transition index
        uint256 transitionIndex = votingContract.stateTransitionCount();
        
        // Get the storage updates
        bytes memory updates = votingContract.operatorExecuteVote(transitionIndex);
        
        // Get test BLS points
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();
        
        bytes4 targetFunction = bytes4(sha256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"));
        
        // Generate a valid message hash
        bytes32 validMsgHash = sha256(abi.encodePacked(
            votingContract.namespace(),
            transitionIndex,
            address(votingContract),
            targetFunction,
            updates
        ));
        
        // Mock the BLS verification
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector,
                validMsgHash,
                apk,
                apkG2,
                sigma
            ),
            abi.encode(true, true)
        );
        
        // Make sure testUser has enough ETH
        vm.deal(testUser, 10 ether);
        
        // Execute the vote
        vm.prank(testUser);
        (bool success, ) = address(votingContract).call{value: 0.1 ether}(
            abi.encodeWithSelector(
                votingContract.writeExecuteVote.selector,
                validMsgHash,
                apk,
                apkG2,
                sigma,
                updates,
                transitionIndex,
                address(votingContract),
                targetFunction
            )
        );
        require(success, "Call failed");
        
        // Verify the payment was made
        assertEq(address(paymentContract).balance, 0.1 ether, "Payment contract should have 0.1 ETH");
        
        // Calculate expected power with transition index
        uint256 expectedPower = (uint160(address(this)) * transitionIndex) + (uint160(voter1) * transitionIndex);
        
        // Verify the voting power was updated correctly - get it directly from the contract
        uint256 actualPower = votingContract.currentTotalVotingPower();
        assertEq(actualPower, expectedPower, "Total voting power should be updated correctly");
    }

    function testPaymentContractWithdrawal() public {
        // Make sure we start with a clean state 
        assertEq(address(paymentContract).balance, 0, "Payment contract should start with 0 balance");
        
        // Execute a payment to have some funds in the payment contract
        _executePayment();
        
        // Check initial balance
        assertEq(address(paymentContract).balance, 0.1 ether, "Payment contract should have 0.1 ETH");
        
        // Setup a receiver address
        address payable receiver = payable(address(0x789));
        vm.deal(receiver, 0); // Make sure receiver starts with 0 balance
        
        // Remember owner from the setup
        address owner = paymentContract.owner();
        
        // Owner withdraws the funds
        vm.prank(owner);
        paymentContract.withdraw(receiver);
        
        // Check that funds were transferred correctly
        assertEq(address(paymentContract).balance, 0, "Payment contract should be empty");
        assertEq(receiver.balance, 0.1 ether, "Receiver should have received 0.1 ETH");
    }

    function testCannotWithdrawAsNonOwner() public {
        // Make sure we start with a clean state
        assertEq(address(paymentContract).balance, 0, "Payment contract should start with 0 balance");
        
        // Execute a payment to have some funds in the contract
        _executePayment();
        
        // Setup a receiver address
        address payable receiver = payable(address(0x789));
        
        // Try to withdraw as non-owner (using testUser which is not the owner)
        // The expectRevert must come BEFORE the call that's expected to revert
        vm.expectRevert("Only owner can withdraw");
        vm.prank(testUser);
        paymentContract.withdraw(receiver);
    }

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
        
        bytes4 targetFunction = bytes4(sha256("writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"));
        
        // Generate a valid message hash
        bytes32 validMsgHash = sha256(abi.encodePacked(
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

    function testFrontRunSameBlockReverts() public {
        // 1) Add a voter so we move to transitionIndex = 2
        //    (initial deploy = 1, first addVoter = 2)
        address voter1 = address(0x222);
        votingContract.addVoter(voter1);

        // 2) aggregator obtains "correct" updates for the *current* transition index,
        //    which is now 2.
        uint256 staleTransitionIndex = votingContract.stateTransitionCount();
        bytes memory staleUpdates = votingContract.operatorExecuteVote(staleTransitionIndex);

        // 3) aggregator calculates the BLS signature for `staleTransitionIndex`.
        //    We'll mock it again. (Same approach as your other tests.)
        (BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma) = _createTestBLSPoints();
        bytes4 targetFunction = bytes4(
            keccak256(
                "writeExecuteVote(bytes32,BN254.G1Point,BN254.G2Point,BN254.G1Point,bytes,uint256,address,bytes4)"
            )
        );

        // This is the hash for transitionIndex = 2
        bytes32 msgHashStale = sha256(
            abi.encodePacked(
                votingContract.namespace(),
                staleTransitionIndex,
                address(votingContract),
                targetFunction,
                staleUpdates
            )
        );

        // Mock the BLS check to succeed for that stale hash
        vm.mockCall(
            BLS_SIG_CHECKER,
            abi.encodeWithSelector(
                BLSSignatureChecker.trySignatureAndApkVerification.selector,
                msgHashStale,
                apk,
                apkG2,
                sigma
            ),
            abi.encode(true, true)
        );

        // 4) Now, a front-run TX occurs in the *same block* that changes state again.
        //    In Foundry, each vm.call typically mines a separate block by default.
        //    But we can artificially keep the same block by rolling back the block number.
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


        // Because the aggregator's `transitionIndex` param is now stale (2),
        // the contract code checks:
        //   require(expectedHash == msgHash, "Invalid signature");
        // However, the aggregator's "expectedHash" is for index 2,
        // while the contract's BLS checks and storage are effectively beyond that.
        // We expect "Invalid signature" revert because the contract's state
        // doesn't match the aggregator's stale hash context anymore.
        (bool success, bytes memory data) = address(votingContract).call{value: 0.1 ether}(
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
        // Optionally, you could also parse the revert reason from 'data' to confirm
        // it's "Invalid signature". For example:
        if (data.length > 0) {
            // The revert reason is ABI-encoded; the simplest approach is to check it as bytes
            // or do a substring match. This snippet is optional, for demonstration:
            // string memory reason = _getRevertMsg(data);
            // assertEq(reason, "Invalid signature");
        }
    }

}
