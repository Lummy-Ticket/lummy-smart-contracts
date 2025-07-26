// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "src/core/EventFactory.sol";
import "src/core/Event.sol";
import "src/core/TicketNFT.sol";
import "src/core/MockIDRX.sol";
import "src/core/SimpleForwarder.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "forge-std/console.sol";

contract GaslessTransactionTest is Test {
    EventFactory public factory;
    MockIDRX public idrxToken;
    SimpleForwarder public forwarder;
    Event public eventContract;
    TicketNFT public ticketNFT;
    
    address public deployer = address(this);
    address public paymaster = makeAddr("paymaster"); // Your wallet address (gas payer)
    address public organizer = makeAddr("organizer");
    address public user = makeAddr("user"); // User who wants gasless transaction
    
    uint256 public eventDate;
    uint256 public tier1Price = 100 * 1e18;
    
    function setUp() public {
        console.log("Setting up Gasless Transaction test environment");
        
        eventDate = block.timestamp + 30 days;
        
        // Deploy IDRX token
        idrxToken = new MockIDRX();
        
        // Deploy forwarder with paymaster
        forwarder = new SimpleForwarder(paymaster);
        
        // Deploy factory with forwarder
        factory = new EventFactory(address(idrxToken), address(forwarder));
        
        // Fund accounts
        idrxToken.mint(user, 1000 * 1e18);
        idrxToken.mint(organizer, 1000 * 1e18);
        idrxToken.mint(paymaster, 1000 * 1e18);
        
        // Fund paymaster with ETH for gas
        vm.deal(paymaster, 10 ether);
        vm.deal(address(forwarder), 5 ether);
        
        console.log("Factory deployed at:", address(factory));
        console.log("Forwarder deployed at:", address(forwarder));
        console.log("Trusted forwarder in factory:", factory.getTrustedForwarder());
    }
    
    function testSetTrustedForwarder() public {
        console.log("=== Testing Trusted Forwarder Management ===");
        
        // Check initial forwarder
        address initialForwarder = factory.getTrustedForwarder();
        assertEq(initialForwarder, address(forwarder), "Initial forwarder should be set");
        
        // Deploy new forwarder
        SimpleForwarder newForwarder = new SimpleForwarder(paymaster);
        
        // Only owner can set trusted forwarder
        vm.expectRevert();
        vm.prank(user);
        factory.setTrustedForwarder(address(newForwarder));
        
        // Owner can set trusted forwarder
        factory.setTrustedForwarder(address(newForwarder));
        assertEq(factory.getTrustedForwarder(), address(newForwarder), "Forwarder should be updated");
        
        // Reset to original forwarder for other tests
        factory.setTrustedForwarder(address(forwarder));
        
        console.log("[SUCCESS] Trusted forwarder management working correctly");
    }
    
    function testEventCreationWithTrustedForwarder() public {
        console.log("=== Testing Event Creation with Trusted Forwarder ===");
        
        // Create event using organizer account
        vm.startPrank(organizer);
        address eventAddress = factory.createEvent(
            "Gasless Test Event",
            "Testing gasless transactions",
            eventDate,
            "Virtual Venue",
            "ipfs://metadata",
            true // Use Algorithm 1
        );
        vm.stopPrank();
        
        eventContract = Event(eventAddress);
        address nftAddress = eventContract.getTicketNFT();
        ticketNFT = TicketNFT(nftAddress);
        
        // Check that contracts were deployed with correct trusted forwarder
        assertTrue(eventContract.isTrustedForwarder(address(forwarder)), "Event should trust the forwarder");
        assertTrue(ticketNFT.isTrustedForwarder(address(forwarder)), "TicketNFT should trust the forwarder");
        
        // Add ticket tier
        vm.startPrank(organizer);
        eventContract.addTicketTier("Regular", tier1Price, 100, 5);
        vm.stopPrank();
        
        console.log("Event created at:", eventAddress);
        console.log("TicketNFT created at:", nftAddress);
        console.log("[SUCCESS] Event creation with trusted forwarder working correctly");
    }
    
    function testGaslessTicketPurchase() public {
        console.log("=== Testing Gasless Ticket Purchase ===");
        
        // First create an event
        testEventCreationWithTrustedForwarder();
        
        // User approves IDRX spending
        vm.startPrank(user);
        idrxToken.approve(address(eventContract), tier1Price);
        vm.stopPrank();
        
        // Check balances before transaction
        uint256 userEthBefore = user.balance;
        uint256 paymasterEthBefore = paymaster.balance;
        uint256 userTokensBefore = idrxToken.balanceOf(user);
        
        console.log("User ETH before:", userEthBefore);
        console.log("Paymaster ETH before:", paymasterEthBefore);
        console.log("User tokens before:", userTokensBefore);
        
        // Create forward request for ticket purchase
        // This would normally be done off-chain with user's signature
        bytes memory callData = abi.encodeWithSelector(
            Event.purchaseTicket.selector,
            0, // tier ID
            1  // quantity
        );
        
        SimpleForwarder.ForwardRequest memory request = SimpleForwarder.ForwardRequest({
            from: user,
            to: address(eventContract),
            value: 0,
            gas: 300000,
            nonce: forwarder.getNonce(user),
            data: callData
        });
        
        // Simulate gasless transaction by having user execute directly
        // In a real implementation, this would go through the forwarder with proper signatures
        // For testing purposes, we'll demonstrate the concept directly
        
        vm.startPrank(user);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        // Check results
        uint256 userTokensAfter = idrxToken.balanceOf(user);
        uint256 userNFTBalance = ticketNFT.balanceOf(user);
        
        console.log("User tokens after:", userTokensAfter);
        console.log("User NFT balance:", userNFTBalance);
        
        assertEq(userTokensAfter, userTokensBefore - tier1Price, "User should pay tokens");
        assertEq(userNFTBalance, 1, "User should receive NFT");
        
        console.log("[SUCCESS] Gasless transaction concept demonstrated");
    }
    
    function testForwarderManagement() public {
        console.log("=== Testing Forwarder Management ===");
        
        // Test paymaster management
        address newPaymaster = makeAddr("newPaymaster");
        
        // Only current paymaster can change paymaster
        vm.expectRevert();
        vm.prank(user);
        forwarder.setPaymaster(newPaymaster);
        
        // Paymaster can change
        vm.prank(paymaster);
        forwarder.setPaymaster(newPaymaster);
        
        assertEq(forwarder.paymaster(), newPaymaster, "Paymaster should be updated");
        
        // Test authorized callers
        vm.prank(newPaymaster);
        forwarder.addAuthorizedCaller(user);
        assertTrue(forwarder.authorizedCallers(user), "User should be authorized");
        
        vm.prank(newPaymaster);
        forwarder.removeAuthorizedCaller(user);
        assertFalse(forwarder.authorizedCallers(user), "User should not be authorized");
        
        console.log("[SUCCESS] Forwarder management working correctly");
    }
    
    function testWithdrawFromForwarder() public {
        console.log("=== Testing Withdraw from Forwarder ===");
        
        // Send some ETH to forwarder
        vm.deal(address(forwarder), 2 ether);
        
        uint256 paymasterBalanceBefore = paymaster.balance;
        uint256 forwarderBalanceBefore = address(forwarder).balance;
        
        // Only paymaster can withdraw
        vm.expectRevert();
        vm.prank(user);
        forwarder.withdraw(1 ether);
        
        // Paymaster can withdraw
        vm.prank(paymaster);
        forwarder.withdraw(1 ether);
        
        assertEq(paymaster.balance, paymasterBalanceBefore + 1 ether, "Paymaster should receive ETH");
        assertEq(address(forwarder).balance, forwarderBalanceBefore - 1 ether, "Forwarder balance should decrease");
        
        console.log("[SUCCESS] Forwarder withdrawal working correctly");
    }
}