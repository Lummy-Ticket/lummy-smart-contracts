// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "src/legacy/contracts/Event.sol";
import "src/shared/contracts/TicketNFT.sol";

// Stack-safe deployer to avoid "Stack too deep" error
contract EventDeployer {
    // Struct to pack parameters and avoid stack depth issues
    struct DeployParams {
        address sender;
        string name;
        string description;
        uint256 date;
        string venue;
        string ipfsMetadata;
        address idrxToken;
        address platformFeeReceiver;
        bool useAlgorithm1;
        uint256 eventId;
        address trustedForwarder;
    }
    
    function deployEventAndTicket(
        DeployParams calldata params
    ) external returns (address eventAddress, address ticketNFTAddress) {
        // Deploy Event with trusted forwarder
        Event newEvent = new Event(params.trustedForwarder);
        
        // Deploy TicketNFT with trusted forwarder
        TicketNFT newTicketNFT = new TicketNFT(params.trustedForwarder);
        
        // Initialize contracts
        _initializeContracts(newEvent, newTicketNFT, params);
        
        return (address(newEvent), address(newTicketNFT));
    }
    
    // Separate function to avoid stack depth issues
    function _initializeContracts(
        Event newEvent,
        TicketNFT newTicketNFT,
        DeployParams calldata params
    ) private {
        // Initialize Event
        newEvent.initialize(
            params.sender,
            params.name,
            params.description,
            params.date,
            params.venue,
            params.ipfsMetadata
        );
        
        // Initialize TicketNFT
        if (params.useAlgorithm1) {
            newTicketNFT.initializeWithEventId(params.name, "TIX", address(newEvent), params.eventId);
        } else {
            newTicketNFT.initialize(params.name, "TIX", address(newEvent));
        }
        
        // Set algorithm mode before setting up NFT
        if (params.useAlgorithm1) {
            newEvent.setAlgorithm1(true, params.eventId);
        }
        
        // Set up Event with TicketNFT
        newEvent.setTicketNFT(
            address(newTicketNFT),
            params.idrxToken,
            params.platformFeeReceiver
        );
    }
}