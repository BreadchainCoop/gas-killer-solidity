// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract VotingContract {
    // List of current voters
    address[] public voters;

    // Tracks our “current” total voting power.
    uint256 public currentTotalVotingPower;

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
        currentTotalVotingPower = getCurrentTotalVotingPower(block.number);

        // Check if the total voting power is even
        bool votePassed = (currentTotalVotingPower % 2 == 0);

        // Return whether the vote passed
        return votePassed;
    }

    // /**
    //  * @notice Overloaded version with parameters. In a real contract,
    //  *         you would verify the aggBlsSig, etc. Here we just show the structure.
    //  */
    // function executeVote(
    //     bytes calldata aggBlsSig,
    //     uint256 newCurrentVotingPower,
    //     uint256 blockNumber
    // ) external {
    //     // Validate or use aggBlsSig as needed (omitted here).
    //     // Possibly also verify the blockNumber in a real scenario.

    //     // Update
    //     currentTotalVotingPower = newCurrentVotingPower;

    //     // Check that the new total is even
    //     require(
    //         currentTotalVotingPower % 2 == 0,
    //         "Vote did not pass: total voting power is odd."
    //     );
    // }

    // /**
    //  * @notice Stub “slashForVote” function. In a real setting, this would have
    //  *         logic to slash stake based on some proof of misbehavior, etc.
    //  */
    // function slashForVote(
    //     bytes calldata aggBlsSig,
    //     uint256 newCurrentVotingPower,
    //     uint256 blockNumber
    // ) external {
    //     // In practice, you'd implement slashing logic here.
    //     // This is just a placeholder.
    // }
}
