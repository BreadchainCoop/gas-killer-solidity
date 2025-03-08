// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

contract StateTracker {
    // `keccak256("gasKiller.stateTracker") - 1
    bytes32 internal constant _stateTrackerSlot = 0xdebfdfd5a50ad117c10898d68b5ccf0893c6b40d4f443f902e2e7646601bdeaf;

    modifier trackState() {
        assembly {
            let count := sload(_stateTrackerSlot)
            sstore(_stateTrackerSlot, add(0x01, count))
        }
        _;
    }

    function stateTransitionCount() public view returns (uint256 count) {
        assembly {
            count := sload(_stateTrackerSlot)
        }
    }
}
