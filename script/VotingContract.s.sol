// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/VotingContract.sol";
import "../src/Payments.sol";

contract DeployVotingSystem is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the PaymentContract first
        console.log("Deploying PaymentContract...");
        PaymentContract paymentContract = new PaymentContract();
        console.log("PaymentContract deployed at:", address(paymentContract));

        // Deploy the VotingContract, passing in the PaymentContract address
        console.log("Deploying VotingContract...");
        VotingContract votingContract = new VotingContract(
            address(paymentContract)
        );
        console.log("VotingContract deployed at:", address(votingContract));

        // Print initial state
        console.log("\n=== Initial State ===");
        console.log("Current transition index:", votingContract.stateTransitionCount());
        console.log("Current total voting power:", votingContract.currentTotalVotingPower());
        console.log("Last vote passed:", votingContract.lastVotePassed());

        // First vote execution
        console.log("\n=== First Vote Execution ===");
        
        // 1. Get the storage updates from the operatorExecuteVote view function
        uint256 transitionIndex = votingContract.stateTransitionCount();
        bytes memory storageUpdates = votingContract.operatorExecuteVote(transitionIndex);
        console.log("Generated storage updates for transition index:", transitionIndex);
        
        // 2. Execute the vote by applying the storage updates
        console.log("Executing vote with storage updates...");
        bytes memory result = votingContract.writeExecuteVoteTest{value: 0.1 ether}(storageUpdates);
        
        // 3. Decode and log the results
        (uint256 votingPower, bool votePassed) = abi.decode(result, (uint256, bool));
        console.log("Vote execution complete:");
        console.log(" - New total voting power:", votingPower);
        console.log(" - Vote passed:", votePassed);
        console.log(" - New transition index:", votingContract.stateTransitionCount());

        // Second vote execution
        console.log("\n=== Second Vote Execution ===");
        
        // 1. Get the storage updates for the new transition index
        transitionIndex = votingContract.stateTransitionCount();
        storageUpdates = votingContract.operatorExecuteVote(transitionIndex);
        console.log("Generated storage updates for transition index:", transitionIndex);
        
        // 2. Execute the vote again
        console.log("Executing vote with storage updates...");
        result = votingContract.writeExecuteVoteTest{value: 0.1 ether}(storageUpdates);
        
        // 3. Decode and log the results
        (votingPower, votePassed) = abi.decode(result, (uint256, bool));
        console.log("Vote execution complete:");
        console.log(" - New total voting power:", votingPower);
        console.log(" - Vote passed:", votePassed);
        console.log(" - New transition index:", votingContract.stateTransitionCount());

        // Print summary
        console.log("\n=== Deployment Summary ===");
        console.log("PaymentContract:", address(paymentContract));
        console.log("VotingContract:", address(votingContract));
        console.log("Final transition index:", votingContract.stateTransitionCount());
        console.log("Final voting power:", votingContract.currentTotalVotingPower());
        console.log("Final vote result:", votingContract.lastVotePassed());

        vm.stopBroadcast();
    }
}
