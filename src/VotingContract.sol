// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@eigenlayer-middleware/BLSSignatureChecker.sol";
import "@eigenlayer-middleware/interfaces/IInstantSlasher.sol";
import "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import "./Payments.sol";
import "./StateTracker.sol";

contract VotingContract is StateTracker {
    // ------------------------------------------------------------------------
    // 1) Hardcoded storage slot constants, using precomputed keccak256 values
    // ------------------------------------------------------------------------
    // keccak256("VotingContract.currentTotalVotingPower")
    bytes32 internal constant CURRENT_TOTAL_VOTING_POWER_SLOT =
        0x2ef300128d8bab26260cc62ee81b836797fdb69a87c72ee4ee954f2b31f5fc7e;

    // keccak256("VotingContract.lastVotePassed")
    bytes32 internal constant LAST_VOTE_PASSED_SLOT =
        0x0df3fffaac6beb149ae42659747af9c815cf8bb1c2f1a56df229f8ec2f1b7b63;

    // ------------------------------------------------------------------------
    // 2) Other state variables
    // ------------------------------------------------------------------------
    address[] public voters;
    PaymentContract public paymentContract;

    BLSSignatureChecker public blsSignatureChecker;
    address public constant BLS_SIG_CHECKER = address(0xCa249215E082E17c12bB3c4881839A3F883e5C6B);

    bytes public constant namespace = "_COMMONWARE_AGGREGATION_";

    mapping(uint256 => bytes) public votersArrayStorage;

    IInstantSlasher public slasher;
    ISlashingRegistryCoordinator public registryCoordinator;

    error InvalidTransitionIndex();

    // ------------------------------------------------------------------------
    // 3) Constructor
    // ------------------------------------------------------------------------
    constructor(address _paymentContract) {
        // Initialize the BLS signature checker
        blsSignatureChecker = BLSSignatureChecker(BLS_SIG_CHECKER);

        // Initialize the PaymentContract
        paymentContract = PaymentContract(_paymentContract);

        // Initialize the "voters" with `msg.sender`
        voters.push(msg.sender);

        // Increment the state transition count (from StateTracker)
        assembly {
            sstore(_stateTrackerSlot, add(0x01, sload(_stateTrackerSlot)))
        }

        // Store the new voters array under that initial transition
        votersArrayStorage[stateTransitionCount()] = abi.encode(voters);
    }

    // ------------------------------------------------------------------------
    // 4) Internal getters/setters for manual storage slots
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
    // 5) Public getters for scripts/tests
    // ------------------------------------------------------------------------
    function currentTotalVotingPower() external view returns (uint256) {
        return _getCurrentTotalVotingPower();
    }

    function lastVotePassed() external view returns (bool) {
        return _getLastVotePassed();
    }

    // ------------------------------------------------------------------------
    // 6) Voter Management & Queries
    // ------------------------------------------------------------------------
    function addVoter(address _voter) external trackState {
        voters.push(_voter);
        bytes memory encodedVoters = abi.encode(voters);
        votersArrayStorage[stateTransitionCount()] = encodedVoters;
    }

    function getCurrentVotersArray() external view returns (bytes memory) {
        return abi.encode(voters);
    }

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

        address[] memory votersAtIndex = abi.decode(storedArray, (address[]));
        uint256 sumVal = 0;

        for (uint256 i = 0; i < votersAtIndex.length; i++) {
            // Example formula
            sumVal += (uint160(votersAtIndex[i]) * transitionIndex);
        }
        return sumVal;
    }

    // ------------------------------------------------------------------------
    // 7) Standard "executeVote"
    // ------------------------------------------------------------------------
    function executeVote() external trackState returns (bool) {
        uint256 newVotingPower = getCurrentTotalVotingPower(stateTransitionCount());

        _setCurrentTotalVotingPower(newVotingPower);

        bool votePassed = (newVotingPower % 2 == 0);
        _setLastVotePassed(votePassed);

        return votePassed;
    }

    // ------------------------------------------------------------------------
    // 8) operatorExecuteVote / writeExecuteVote / slashExecVote
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

        bytes32 expectedHash =
            sha256(abi.encodePacked(namespace, transitionIndex, targetAddr, targetFunction, storageUpdates));
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
        bytes32 expectedHash =
            sha256(abi.encodePacked(namespace, transitionIndex, targetAddr, targetFunction, storageUpdates));
        bool signatureValid = (expectedHash == msgHash);

        if (!signatureValid) {
            // SLASHING logic here if desired
            return abi.encode(true); // Slashing needed
        }

        (bool pairingSuccessful, bool signatureIsValid) =
            blsSignatureChecker.trySignatureAndApkVerification(msgHash, apk, apkG2, sigma);

        if (!pairingSuccessful || !signatureIsValid) {
            // SLASHING logic here if desired
            return abi.encode(true); // Slashing needed
        }

        bytes memory correctUpdates = this.operatorExecuteVote(transitionIndex);
        bool updatesValid = (keccak256(storageUpdates) == keccak256(correctUpdates));

        bool slashNeeded = !updatesValid;
        if (slashNeeded) {
            // SLASHING logic if desired
        }

        return abi.encode(slashNeeded);
    }

    // ------------------------------------------------------------------------
    // 9) Test-only skipping signature verification
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // 10) Set Slashing Contracts (production usage)
    // ------------------------------------------------------------------------
    function setSlashingContracts(address _slasher, address _registryCoordinator) external {
        // In production, add access control
        slasher = IInstantSlasher(_slasher);
        registryCoordinator = ISlashingRegistryCoordinator(_registryCoordinator);
    }
}
