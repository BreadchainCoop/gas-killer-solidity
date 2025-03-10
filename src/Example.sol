pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Example {
    uint256 public count;
    event Increment(uint256 count);

    function increment() public {
        uint256 balance = IERC20(0x0000000000000000000000000000000000000000).balanceOf(address(this)); // This external call cannot be saved 
        if (balance > 0) { // This condition can be saved 
            IERC20(0x0000000000000000000000000000000000000000).transfer(msg.sender, balance); // This external call cannot be saved 
        }
        count++; // This internal write cannot be saved 
        emit Increment(count); // This event cannot be saved 
    }
    
}