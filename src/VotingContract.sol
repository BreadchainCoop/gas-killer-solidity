// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@eigenlayer-middleware/BLSSignatureChecker.sol";
import "@eigenlayer-middleware/interfaces/IInstantSlasher.sol";
import "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import "./Payments.sol";
import "./StateTracker.sol";

contract VotingContract is StateTracker {
    // List of current voters
    address[] public voters;

    // ------------------------------------------------------------------------
    // 1) Hardcoded storage slot constants, using precomputed keccak256 values
    // ------------------------------------------------------------------------
    // keccak256("VotingContract.currentTotalVotingPower")
    bytes32 internal constant CURRENT_TOTAL_VOTING_POWER_SLOT =
        0x2ef300128d8bab26260cc62ee81b836797fdb69a87c72ee4ee954f2b31f5fc7e;

    // keccak256("VotingContract.lastVotePassed")
    bytes32 internal constant LAST_VOTE_PASSED_SLOT = 0x0df3fffaac6beb149ae42659747af9c815cf8bb1c2f1a56df229f8ec2f1b7b63;

    PaymentContract public paymentContract;

    // The BLS signature checker contract
    BLSSignatureChecker public blsSignatureChecker;
    // The address of the BLS signature checker contract
    address public constant BLS_SIG_CHECKER = address(0xB6861c61782aec28a14cF68cECf216Ad7f5F4e2D);

    // Hardcoded namespace matching the Rust constant
    bytes public constant namespace = "_COMMONWARE_AGGREGATION_";

    // We store, for each transition index, an encoded array of voters that existed at that index.
    mapping(uint256 => bytes) public votersArrayStorage;

    // EigenLayer slashing contracts
    IInstantSlasher public slasher;
    ISlashingRegistryCoordinator public registryCoordinator;

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

        // These would be set to actual contract addresses in production
        // slasher = IInstantSlasher(address(0));
        // registryCoordinator = ISlashingRegistryCoordinator(address(0));
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

        _setCurrentTotalVotingPower(newVotingPower);

        bool votePassed = (newVotingPower % 2 == 0);
        _setLastVotePassed(votePassed);

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

        // 3) Build the bytes payload:
        //    sstore(CURRENT_TOTAL_VOTING_POWER_SLOT, newVotingPower)
        //    sstore(LAST_VOTE_PASSED_SLOT, votePassed ? 1 : 0)
        return abi.encodePacked(
            uint8(0),
            CURRENT_TOTAL_VOTING_POWER_SLOT,
            newVotingPower,
            uint8(0),
            LAST_VOTE_PASSED_SLOT,
            votePassed ? uint256(1) : uint256(0)
        );
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
        require(msg.value == 0.1 ether, "Must send exactly 0.1 ETH");
        paymentContract.deposit{value: msg.value}();

        bytes32 expectedHash = sha256(abi.encode(transitionIndex, targetAddr, targetFunction, storageUpdates));
        require(expectedHash == msgHash, "Invalid signature");

        (bool pairingSuccessful, bool signatureIsValid) =
            blsSignatureChecker.trySignatureAndApkVerification(msgHash, apk, apkG2, sigma);
        require(pairingSuccessful, "BLS pairing check failed");
        require(signatureIsValid, "Invalid BLS signature");

        // 2) Apply the storage updates
        uint256 i = 0;
        while (i < storageUpdates.length) {
            require(i + 1 <= storageUpdates.length, "Invalid opcode offset");
            uint8 op = uint8(storageUpdates[i]);
            i++;

            require(op == 0, "Unsupported operation (op must be 0)");

            require(i + 32 <= storageUpdates.length, "Missing slot data");
            uint256 slot;
            assembly {
                slot := calldataload(add(storageUpdates.offset, i))
            }
            i += 32;

            require(i + 32 <= storageUpdates.length, "Missing value data");
            uint256 val;
            assembly {
                val := calldataload(add(storageUpdates.offset, i))
            }
            i += 32;

            assembly {
                sstore(slot, val)
            }
        }

        // 3) Return updated state
        return abi.encode(_getCurrentTotalVotingPower(), _getLastVotePassed());
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
            // SLASHING LOGIC WOULD GO HERE
            /* Commented out for now
            if (address(slasher) != address(0)) {
                // Create slashing parameters
                IAllocationManager.SlashingParams memory slashParams = IAllocationManager.SlashingParams({
                    operator: address(apk), // This would need to be the actual operator address
                    operatorSetId: 0, // Would need actual operator set ID
                    wadsToSlash: new uint256[](1), // Amount to slash
                    strategies: new IStrategy[](1), // Strategies to slash
                    description: "Invalid signature in voting contract"
                });
                
                // Execute slashing via InstantSlasher
                // slasher.fulfillSlashingRequest(slashParams);
            }
            */
            return abi.encode(true); // Slashing needed
        }

        // Verify BLS signature directly using trySignatureAndApkVerification
        (bool pairingSuccessful, bool signatureIsValid) =
            blsSignatureChecker.trySignatureAndApkVerification(msgHash, apk, apkG2, sigma);

        // Check if the signature verification failed
        if (!pairingSuccessful || !signatureIsValid) {
            // SLASHING LOGIC WOULD GO HERE
            /* Commented out for now
            if (address(slasher) != address(0)) {
                // Create slashing parameters for invalid BLS signature
                IAllocationManager.SlashingParams memory slashParams = IAllocationManager.SlashingParams({
                    operator: address(apk), // This would need to be the actual operator address
                    operatorSetId: 0, // Would need actual operator set ID
                    wadsToSlash: new uint256[](1), // Amount to slash
                    strategies: new IStrategy[](1), // Strategies to slash
                    description: "Invalid BLS signature in voting contract"
                });
                
                // Execute slashing via InstantSlasher
                // slasher.fulfillSlashingRequest(slashParams);
            }
            */
            return abi.encode(true); // Slashing needed
        }

        // Calculate what the correct storage updates should be
        bytes memory correctUpdates = this.operatorExecuteVote(transitionIndex);

        // Check if provided storage updates match the correct ones
        bool updatesValid = keccak256(storageUpdates) == keccak256(correctUpdates);

        // Slashing is needed if updates are incorrect
        bool slashNeeded = !updatesValid;

        if (slashNeeded) {
            // SLASHING LOGIC WOULD GO HERE
            /* Commented out for now
            if (address(slasher) != address(0)) {
                // Get operator address from registry using APK
                // address operatorAddress = registryCoordinator.getOperatorFromId(keccak256(abi.encode(apk)));
                
                // Create slashing parameters for incorrect storage updates
                IAllocationManager.SlashingParams memory slashParams = IAllocationManager.SlashingParams({
                    operator: address(0), // Would be populated with actual operator address
                    operatorSetId: 0,
                    wadsToSlash: new uint256[](1),
                    strategies: new IStrategy[](1),
                    description: "Incorrect storage updates in voting contract"
                });
                
                // Execute slashing via InstantSlasher
                // slasher.fulfillSlashingRequest(slashParams);
            }
            */
        }

        // Return slashing status
        return abi.encode(slashNeeded);
    }

    // Test-only version of writeExecuteVote that skips signature verification
    function writeExecuteVoteTest(bytes calldata storageUpdates) external payable trackState returns (bytes memory) {
        require(msg.value == 0.1 ether, "Must send exactly 0.1 ETH");
        paymentContract.deposit{value: msg.value}();

        uint256 i = 0;
        while (i < storageUpdates.length) {
            require(i + 1 <= storageUpdates.length, "Invalid opcode offset");
            uint8 op = uint8(storageUpdates[i]);
            i++;

            require(op == 0, "Unsupported operation (op must be 0)");

            require(i + 32 <= storageUpdates.length, "Missing slot data");
            uint256 slot;
            assembly {
                slot := calldataload(add(storageUpdates.offset, i))
            }
            i += 32;

            require(i + 32 <= storageUpdates.length, "Missing value data");
            uint256 val;
            assembly {
                val := calldataload(add(storageUpdates.offset, i))
            }
            i += 32;

            assembly {
                sstore(slot, val)
            }
        }

        return abi.encode(_getCurrentTotalVotingPower(), _getLastVotePassed());
    }

    /**
     * @notice Sets the slasher contract
     * @param _slasher The address of the InstantSlasher contract
     * @param _registryCoordinator The address of the SlashingRegistryCoordinator contract
     */
    function setSlashingContracts(address _slasher, address _registryCoordinator) external {
        // In production, add access control here
        slasher = IInstantSlasher(_slasher);
        registryCoordinator = ISlashingRegistryCoordinator(_registryCoordinator);
    }

    // ------------------------------------------------------------------------
    // Internal getters/setters for manual storage slots
    // ------------------------------------------------------------------------
    function _getCurrentTotalVotingPower() internal view returns (uint256 val) {
        assembly {
            val := sload(CURRENT_TOTAL_VOTING_POWER_SLOT)
        }
    }

    function _setCurrentTotalVotingPower(uint256 newVal) internal {
        assembly {
            sstore(CURRENT_TOTAL_VOTING_POWER_SLOT, newVal)
        }
    }

    function _getLastVotePassed() internal view returns (bool val) {
        uint256 raw;
        assembly {
            raw := sload(LAST_VOTE_PASSED_SLOT)
        }
        val = (raw != 0);
    }

    function _setLastVotePassed(bool newVal) internal {
        assembly {
            sstore(LAST_VOTE_PASSED_SLOT, newVal)
        }
    }

    // ------------------------------------------------------------------------
    // Public getters for scripts/tests
    // ------------------------------------------------------------------------
    function currentTotalVotingPower() external view returns (uint256) {
        return _getCurrentTotalVotingPower();
    }

    function lastVotePassed() external view returns (bool) {
        return _getLastVotePassed();
    }
}
