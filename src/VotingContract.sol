// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@eigenlayer-middleware/BLSSignatureChecker.sol";
import "./Payments.sol";
import "./StateTracker.sol";

error HASH_MISMATCH(bytes32 expected, bytes32 actual, bytes params);

contract VotingContract is StateTracker {
    // List of current voters
    address[] public voters;

    // Tracks our "current" total voting power.
    uint256 public currentTotalVotingPower;
    // Tracks if the last vote passed
    bool public lastVotePassed;

    PaymentContract public paymentContract;

    // The BLS signature checker contract
    BLSSignatureChecker public blsSignatureChecker;
    // The address of the BLS signature checker contract
    address public constant BLS_SIG_CHECKER = address(0x870679E138bCdf293b7Ff14dD44b70FC97e12fc0);

    // Hardcoded namespace matching the Rust constant
    bytes public constant namespace = "_COMMONWARE_AGGREGATION_";

    // We store, for each transition index, an encoded array of voters that existed at that index.
    mapping(uint256 => bytes) public votersArrayStorage;

    // add revert
    error InvalidTransitionIndex();

    constructor(address _paymentContract) {
        // Initialize the BLS signature checker
        blsSignatureChecker = BLSSignatureChecker(BLS_SIG_CHECKER);
        paymentContract = PaymentContract(_paymentContract);
        voters.push(msg.sender);
        assembly {
            sstore(_stateTrackerSlot, add(0x01, sload(_stateTrackerSlot)))
        }
        votersArrayStorage[stateTransitionCount()] = abi.encode(voters);
    }

    /**
     * @notice Adds a new voter and saves the updated voters array
     *         into the mapping under the current transition index.
     */
    function addVoter(address _voter) external trackState {
        voters.push(_voter);
        // Encode and store the updated voters array for this index.
        bytes memory encodedVoters = abi.encode(voters);
        votersArrayStorage[stateTransitionCount()] = encodedVoters;
    }

    /**
     * @notice Returns the current in-memory voters array (as an ABI-encoded bytes array).
     *         If you want the array of addresses, just do `return voters;` in a real contract,
     *         but this matches your requirement for returning bytes.
     */
    function getCurrentVotersArray() external view returns (bytes memory) {
        return abi.encode(voters);
    }

    /**
     * @notice Given a transition index, decodes the voters array that was stored at that index
     *         and computes the total voting power:
     *         sum( uint160(voterAddress) * transitionIndex ).
     */
    function getCurrentTotalVotingPower(uint256 transitionIndex) public view returns (uint256) {
        bytes memory storedArray = votersArrayStorage[transitionIndex];

        uint256 transNum = transitionIndex;
        while (storedArray.length == 0 && transNum > 0) {
            if (transNum == 0) {
                return 0;
            }
            transNum--;
            storedArray = votersArrayStorage[transNum];
        }

        // Decode back the array of addresses
        address[] memory votersAtIndex = abi.decode(storedArray, (address[]));

        uint256 sumVal = 0;
        for (uint256 i = 0; i < votersAtIndex.length; i++) {
            sumVal += (uint160(votersAtIndex[i]) * transitionIndex);
        }
        return sumVal;
    }

    /**
     * @notice Example "executeVote" that recomputes
     *         the currentTotalVotingPower for the latest transition index
     *         and returns true if it's even, indicating the vote "passes."
     */
    function executeVote() external trackState returns (bool) {
        uint256 newVotingPower = getCurrentTotalVotingPower(stateTransitionCount());

        // Update the current total voting power.
        currentTotalVotingPower = newVotingPower;

        // Check if the total voting power is even
        bool votePassed = (newVotingPower % 2 == 0);

        // Store whether this vote passed
        lastVotePassed = votePassed;

        // Return whether the vote passed
        return votePassed;
    }

    // ------------------------------------------------------------------------
    //  THREE ADDITIONAL EXECUTE/SLASH FUNCTIONS
    // ------------------------------------------------------------------------

    function operatorExecuteVote(uint256 transitionIndex) external view returns (bytes memory) {
        // 1) Calculate new voting power
        uint256 newVotingPower = getCurrentTotalVotingPower(transitionIndex);

        // 2) Determine if vote passes (true if even)
        bool votePassed = (newVotingPower % 2 == 0);

        // 3) Build the bytes payload to do:
        //    sstore(1, newVotingPower)
        //    sstore(2, votePassed ? 1 : 0 )
        // Using the format:
        //   - 1 byte: 0 => indicates "SSTORE"
        //   - 32 bytes: slot index
        //   - 32 bytes: value

        bytes memory encoded = abi.encodePacked(
            // SSTORE currentTotalVotingPower
            uint8(0),
            uint256(1),
            newVotingPower,
            // SSTORE lastVotePassed
            uint8(0),
            uint256(2),
            votePassed ? uint256(1) : uint256(0)
        );

        return encoded;
    }

    function writeExecuteVote(
        bytes32 msgHash,
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory sigma,
        bytes calldata storageUpdates,
        uint256 transitionIndex,
        address targetAddr,
        bytes4 targetFunction
    ) external payable trackState returns (bytes memory) {
        require(transitionIndex + 1 == stateTransitionCount(), InvalidTransitionIndex());
        // Check required ETH payment upfront
        require(msg.value == 0.1 ether, "Must send exactly 0.1 ETH");

        // Forward the 0.1 ETH to the PaymentContract
        paymentContract.deposit{value: msg.value}();

        //check that those 4 with namespace match the hash
        bytes32 expectedHash =
            sha256(abi.encode(transitionIndex, targetAddr, targetFunction, storageUpdates));
        // require(expectedHash == msgHash, "Invalid signature");
        if (expectedHash != msgHash) {
            revert HASH_MISMATCH(expectedHash, msgHash, abi.encodePacked(namespace, transitionIndex, targetAddr, targetFunction, storageUpdates));
        }

        // ------------------------------------------------
        // 1) Verify BLS signature directly using trySignatureAndApkVerification
        // ------------------------------------------------
        (bool pairingSuccessful, bool signatureIsValid) =
            blsSignatureChecker.trySignatureAndApkVerification(msgHash, apk, apkG2, sigma);

        // Check if the signature verification was successful
        require(pairingSuccessful, "BLS pairing check failed");
        require(signatureIsValid, "Invalid BLS signature");
        currentTotalVotingPower = 1;
        lastVotePassed = true;
        // ------------------------------------------------
        // 2) Apply the storage updates
        // ------------------------------------------------
        // uint256 i = 0;
        // while (i < storageUpdates.length) {
        //     // First byte is the operation (must be 0 for SSTORE).
        //     require(i + 1 <= storageUpdates.length, "Invalid opcode offset");
        //     uint8 op = uint8(storageUpdates[i]);
        //     i++;

        //     // We only support SSTORE (op = 0) in this example
        //     require(op == 0, "Unsupported operation (op must be 0)");

        //     // Next 32 bytes is the storage slot
        //     require(i + 32 <= storageUpdates.length, "Missing slot data");
        //     uint256 slot;
        //     assembly {
        //         slot := calldataload(add(storageUpdates.offset, i))
        //     }
        //     i += 32;

        //     // Next 32 bytes is the value
        //     require(i + 32 <= storageUpdates.length, "Missing value data");
        //     uint256 val;
        //     assembly {
        //         val := calldataload(add(storageUpdates.offset, i))
        //     }
        //     i += 32;

        //     // Perform the SSTORE
        //     assembly {
        //         sstore(slot, val)
        //     }
        // }

        // // ------------------------------------------------
        // // 3) Return the updated state
        // // ------------------------------------------------
        // return abi.encode(currentTotalVotingPower, lastVotePassed);
    }

    /**
     * @notice Function to verify if a signature is valid and contains correct storage updates
     * @dev Hashes the input parameters and compares with the signature, also verifies storage updates
     * @param msgHash The signature hash to verify
     * @param apk The aggregate public key in G1
     * @param apkG2 The aggregate public key in G2
     * @param sigma The signature to verify
     * @param storageUpdates The storage updates to verify
     * @param transitionIndex The transition index to use for verification
     * @param targetAddr The address that the signature is for
     * @param targetFunction The function that the signature targets
     * @return An encoded result containing verification results
     */
    function slashExecVote(
        bytes32 msgHash,
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory sigma,
        bytes calldata storageUpdates,
        uint256 transitionIndex,
        address targetAddr,
        bytes4 targetFunction
    ) external trackState returns (bytes memory) {
        // Hash all parameters in specified order to create the message hash
        bytes32 expectedHash =
            sha256(abi.encodePacked(namespace, transitionIndex, targetAddr, targetFunction, storageUpdates));

        // Check if signature hash matches expected hash
        bool signatureValid = (expectedHash == msgHash);

        // If signature is invalid, we don't need to check BLS signatures
        if (!signatureValid) {
            return abi.encode(true); // Slashing needed
        }

        // Verify BLS signature directly using trySignatureAndApkVerification
        (bool pairingSuccessful, bool signatureIsValid) =
            blsSignatureChecker.trySignatureAndApkVerification(msgHash, apk, apkG2, sigma);

        // Check if the signature verification failed
        if (!pairingSuccessful || !signatureIsValid) {
            return abi.encode(true); // Slashing needed
        }

        // Calculate what the correct storage updates should be
        bytes memory correctUpdates = this.operatorExecuteVote(transitionIndex);

        // Check if provided storage updates match the correct ones
        bool updatesValid = keccak256(storageUpdates) == keccak256(correctUpdates);

        // Slashing is needed if updates are incorrect
        bool slashNeeded = !updatesValid;

        // Return slashing status
        return abi.encode(slashNeeded);
    }

    // Test-only version of writeExecuteVote that skips signature verification
    function writeExecuteVoteTest(bytes calldata storageUpdates) external payable trackState returns (bytes memory) {
        require(msg.value == 0.1 ether, "Must send exactly 0.1 ETH");

        // Forward the 0.1 ETH to the PaymentContract
        paymentContract.deposit{value: msg.value}();

        // ------------------------------------------------
        // Skip signature verification and apply storage updates directly
        // ------------------------------------------------
        uint256 i = 0;
        while (i < storageUpdates.length) {
            // First byte is the operation (must be 0 for SSTORE).
            require(i + 1 <= storageUpdates.length, "Invalid opcode offset");
            uint8 op = uint8(storageUpdates[i]);
            i++;

            // We only support SSTORE (op = 0) in this example
            require(op == 0, "Unsupported operation (op must be 0)");

            // Next 32 bytes is the storage slot
            require(i + 32 <= storageUpdates.length, "Missing slot data");
            uint256 slot;
            assembly {
                slot := calldataload(add(storageUpdates.offset, i))
            }
            i += 32;

            // Next 32 bytes is the value
            require(i + 32 <= storageUpdates.length, "Missing value data");
            uint256 val;
            assembly {
                val := calldataload(add(storageUpdates.offset, i))
            }
            i += 32;

            // Perform the SSTORE
            assembly {
                sstore(slot, val)
            }
        }

        // ------------------------------------------------
        // Return the updated state
        // ------------------------------------------------
        return abi.encode(currentTotalVotingPower, lastVotePassed);
    }
}
