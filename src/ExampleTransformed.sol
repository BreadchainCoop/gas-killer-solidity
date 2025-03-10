pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./StateTracker.sol";
import "@eigenlayer-middleware/BLSSignatureChecker.sol";

contract Example is StateTracker {
    uint256 public count;
    BLSSignatureChecker public blsSignatureChecker;
    event Increment(uint256 count);

    function increment() trackState public {
        uint256 balance = IERC20(0x0000000000000000000000000000000000000000).balanceOf(address(this)); // This external call cannot be saved 
        if (balance > 0) { // This condition can be saved 
            IERC20(0x0000000000000000000000000000000000000000).transfer(msg.sender, balance); // This external call cannot be saved 
        }
        count++; // This internal write cannot be saved 
        emit Increment(count); // This event cannot be saved 
    }

    function increment(bytes32 msgHash, BN254.G1Point memory apk, BN254.G2Point memory apkG2, BN254.G1Point memory sigma, bytes calldata storageUpdates, uint256 transitionIndex, address targetAddr, bytes4 targetFunction) trackState public {
        bytes32 expectedHash = sha256(abi.encode(transitionIndex, targetAddr, targetFunction, storageUpdates));
        require(expectedHash == msgHash, "Invalid signature");
        require(address(this) == targetAddr, "Invalid target address");

        (bool pairingSuccessful, bool signatureIsValid) =
            blsSignatureChecker.trySignatureAndApkVerification(msgHash, apk, apkG2, sigma);
        require(pairingSuccessful, "BLS pairing check failed");
        require(signatureIsValid, "Invalid BLS signature");

        uint256 offset = 0;
        uint256 updateSize = 64; // 32 bytes for address + 32 bytes for value
        while (offset + updateSize <= storageUpdates.length) {
            // Extract the current update pair
            bytes memory currentUpdate = new bytes(updateSize);
            for (uint256 j = 0; j < updateSize; j++) {
                currentUpdate[j] = storageUpdates[offset + j];
            }
            
            // Decode the update pair
            (address slot, bytes32 value) = abi.decode(currentUpdate, (address, bytes32));
            
            // Apply the storage update
            assembly {
                sstore(slot, value)
            }
            
            // Move to the next update pair
            offset += updateSize;
        }
    }
}