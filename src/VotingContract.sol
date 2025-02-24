// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract VotingContract {
    // List of current voters
    address[] public voters;

    // Tracks our “current” total voting power.
    uint256 public currentTotalVotingPower;
    // Tracks if the last vote passed
    bool public lastVotePassed;


    // We store, for each blockNumber, an encoded array of voters that existed at that point.
    mapping(uint256 => bytes) public votersArrayStorage;

    /**
     * @notice Adds a new voter and saves the updated voters array
     *         into the mapping under the current block number.
     */
    function addVoter(address _voter) external {
        voters.push(_voter);
        // Encode and store the updated voters array for this block.
        bytes memory encodedVoters = abi.encode(voters);
        votersArrayStorage[block.number] = encodedVoters;
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
     * @notice Given a block number, decodes the voters array that was stored at that block
     *         and computes the total voting power:
     *         sum( uint160(voterAddress) * blockNumber ).
     */
    function getCurrentTotalVotingPower(uint256 _blockNumber)
        public
        view
        returns (uint256)
    {
        bytes memory storedArray = votersArrayStorage[_blockNumber];
        // If no voters stored at that block, return 0.
        if (storedArray.length == 0) {
            return 0;
        }

        // Decode back the array of addresses
        address[] memory votersAtBlock = abi.decode(storedArray, (address[]));

        uint256 sumVal = 0;
        for (uint256 i = 0; i < votersAtBlock.length; i++) {
            // Multiply each address (as uint160) by the blockNumber
            sumVal += (uint160(votersAtBlock[i]) * _blockNumber);
        }
        return sumVal;
    }

    /**
     * @notice Example “executeVote” that recomputes
     *         the currentTotalVotingPower for the latest block
     *         and returns true if it's even, indicating the vote “passes.”
     */
    function executeVote() external returns (bool) {
        // Recompute total from the voters stored at the current block.
        uint256 newVotingPower = getCurrentTotalVotingPower(block.number);

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


    function operatorExecuteVote(uint256 blockNumber)
        external
        view
        returns (bytes memory)
    {
        // 1) Calculate new voting power
        uint256 newVotingPower = getCurrentTotalVotingPower(blockNumber);

        // 2) Determine if vote passes (true if even)
        bool votePassed = (newVotingPower % 2 == 0);

        // 3) Build the bytes payload to do:
        //    sstore(1, newVotingPower)
        //    sstore(2, votePassed ? 1 : 0 )
        // Using the format:
        //   - 1 byte: 0 => indicates "SSTORE"
        //   - 32 bytes: slot index
        //   - 32 bytes: value
        //
        // We do that twice: once for currentTotalVotingPower, once for lastVotePassed.
        
        bytes memory encoded = abi.encodePacked(
            // SSTORE currentTotalVotingPower
            uint8(0),              // op = 0 => SSTORE
            uint256(1),            // slot = 1
            newVotingPower,        // value
            // SSTORE lastVotePassed
            uint8(0),              // op = 0 => SSTORE
            uint256(2),            // slot = 2
            votePassed ? uint256(1) : uint256(0) // value
        );

        return encoded;
    }


    function writeExecuteVote(bytes calldata aggSig, bytes calldata storageUpdates)
        external
        returns (bytes memory)
    {
        // In a real system, you’d verify aggSig here before applying the updates.
        // For demonstration, we just parse and apply them.

        uint256 i = 0;
        while (i < storageUpdates.length) {
            require(i + 1 <= storageUpdates.length, "Invalid data offset");
            // First byte is the op code
            uint8 op = uint8(storageUpdates[i]);
            i++;

            // We only handle SSTORE (op == 0)
            require(op == 0, "Unsupported operation (only op=0 allowed)");

            // Next 32 bytes is the slot
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

            // Perform the sstore
            assembly {
                sstore(slot, val)
            }
        }

        // Return the updated voting power and last vote result
        return abi.encode(currentTotalVotingPower, lastVotePassed);
    }


    // function slashExecVote(
    //     bytes calldata aggSig,
    //     bytes calldata someBytes,
    //     uint256 blockNumber
    // ) external returns (bytes memory) {

    // }

}
