# Lummy Algorithm 1 - Pure Web3 NFT Ticket System

## Overview
Algorithm 1 adalah sistem tiket digital berbasis NFT yang sepenuhnya berjalan di blockchain (pure Web3). Ketika user masuk venue, staff scan NFT dan update metadata status dari "valid" menjadi "used" dengan persetujuan user melalui wallet approval. Sistem ini ideal untuk small-medium events (up to 500 attendees) dengan tech-savvy audience.

## Key Features
- **Pure Web3 Architecture**: 100% blockchain-based, no database required
- **ERC-2771 Meta Transactions**: Gasless experience untuk user
- **Factory Pattern**: Independent contract per event
- **Simple QR System**: Token ID only, no encryption needed
- **Event Cancellation**: Built-in refund mechanism
- **Organizer Control**: Full staff management control

## Sistem Flow Detail

### 1. Purchase Flow
```
User → Browse Events → Select Algorithm 1 → Purchase Ticket (Gasless) → NFT Minted
```
- User memilih event yang menggunakan Algorithm 1
- Payment processing menggunakan IDRX stablecoin
- NFT di-mint dengan metadata: `{status: "valid", eventId: eventId, tier: "regular"}`
- NFT dikirim ke wallet user (gasless via ERC-2771)

### 2. Pre-Event Flow
```
Organizer → Setup Staff → Distribute Web Scanner → Configure Whitelist
```
- Organizer menambahkan staff wallet address ke whitelist via smart contract
- Staff menggunakan web-based scanner dengan wallet authentication
- Testing scanner functionality sebelum event

### 3. Venue Entry Flow
```
User Arrive → Staff Scan QR (Token ID) → Blockchain Verification → User Approve → Entry Granted
```
**Detail Steps:**
1. User datang ke venue dan tunjukkan QR code berisi Token ID
2. Staff scan QR menggunakan web-based scanner
3. System extract Token ID dari QR code
4. System verify NFT ownership dan status "valid" via blockchain
5. System initiate metadata update transaction (gasless via ERC-2771)
6. User menerima approval request di wallet
7. User approve transaction untuk update status
8. Metadata status berubah menjadi "used"
9. Entry granted ke venue

## Smart Contract Architecture

### 1. EventFactoryAlgo1.sol
```solidity
contract EventFactoryAlgo1 is ERC2771Context {
    mapping(uint256 => address) public eventContracts;
    uint256 public eventCounter;
    
    event EventCreated(uint256 indexed eventId, address indexed eventContract, address indexed organizer);
    
    function createEvent(
        string memory name,
        string memory description,
        uint256 date,
        string memory venue
    ) external returns (address);
    
    function getEventContract(uint256 eventId) external view returns (address);
}
```

### 2. EventAlgo1.sol
```solidity
contract EventAlgo1 is ERC2771Context, ReentrancyGuard {
    enum EventStatus { Active, Cancelled, Postponed }
    
    struct Event {
        string name;
        string description;
        uint256 date;
        string venue;
        address organizer;
        EventStatus status;
        uint256 totalCapacity;
        bool refundEnabled;
    }
    
    mapping(address => bool) public staffWhitelist;
    mapping(uint256 => bool) public ticketExists;
    
    event StaffAdded(address indexed staff, address indexed organizer);
    event StaffRemoved(address indexed staff, address indexed organizer);
    event EventCancelled(uint256 indexed eventId, uint256 timestamp);
    event TicketStatusUpdated(uint256 indexed tokenId, string oldStatus, string newStatus);
    
    function addStaff(address staff) external onlyOrganizer;
    function removeStaff(address staff) external onlyOrganizer;
    function cancelEvent() external onlyOrganizer;
    function updateTicketStatus(uint256 tokenId) external onlyStaff;
    function purchaseTicket(uint256 tierId, uint256 quantity) external;
}
```

### 3. TicketNFTAlgo1.sol
```solidity
contract TicketNFTAlgo1 is ERC721, ERC2771Context, ReentrancyGuard {
    struct TicketMetadata {
        uint256 eventId;
        string tier;
        string status; // "valid", "used", "refunded"
        uint256 purchaseTime;
        uint256 usedTime;
        address originalOwner;
    }
    
    mapping(uint256 => TicketMetadata) public ticketMetadata;
    
    event TicketMinted(uint256 indexed tokenId, address indexed owner, uint256 eventId);
    event StatusUpdated(uint256 indexed tokenId, string oldStatus, string newStatus);
    event TicketRefunded(uint256 indexed tokenId, address indexed owner);
    
    function mint(address to, uint256 eventId, string memory tier) external returns (uint256);
    function updateStatus(uint256 tokenId, string memory newStatus) external;
    function getTicketStatus(uint256 tokenId) external view returns (string memory);
    function claimRefund(uint256 tokenId) external;
}
```

### 4. Token ID Structure
```solidity
// Format: 1[eventId][tier][sequential]
// Example: 1001200015 = Algorithm 1, Event 1, Tier 2, Ticket 15
function generateTokenId(
    uint256 eventId,    // 3 digits (001-999)
    uint256 tierCode,   // 1 digit (1-9)
    uint256 sequential  // 5 digits (00001-99999)
) internal pure returns (uint256) {
    return (1 * 1e9) + (eventId * 1e6) + (tierCode * 1e5) + sequential;
}
```

## ERC-2771 Meta Transaction Implementation

### 1. Gasless Functions
```solidity
// User tidak perlu bayar gas untuk functions ini
function purchaseTicket(uint256 tierId, uint256 quantity) external {
    address user = _msgSender(); // Real user via meta transaction
    // Purchase logic
}

function updateTicketStatus(uint256 tokenId) external {
    address user = _msgSender(); // Real user via meta transaction
    // Update status logic
}

function transfer(address to, uint256 tokenId) external {
    address user = _msgSender(); // Real user via meta transaction
    // Transfer logic
}
```

### 2. Relayer Configuration
```javascript
// Fixed gas price untuk fairness
const RELAYER_CONFIG = {
    gasPrice: 20_000_000_000, // 20 gwei - fixed price
    gasLimit: 200_000,        // Standard limit
    chainId: 4202             // Lisk Sepolia
};
```

## Frontend Implementation

### 1. Algorithm Selection Interface
```typescript
interface AlgorithmSelectorProps {
    onSelect: (algorithm: 'algo1' | 'algo2') => void;
}

const AlgorithmSelector: React.FC<AlgorithmSelectorProps> = ({ onSelect }) => {
    return (
        <Grid templateColumns="repeat(2, 1fr)" gap={6}>
            <AlgorithmCard
                algorithm="algo1"
                title="Algorithm 1 - Pure Web3"
                description="Best for small-medium events (up to 500 attendees)"
                features={[
                    "Full blockchain experience",
                    "User wallet approval required",
                    "Perfect for tech-savvy audience",
                    "Gasless transactions"
                ]}
                onClick={() => onSelect('algo1')}
            />
        </Grid>
    );
};
```

### 2. Purchase Interface
```typescript
const PurchaseTicket: React.FC<PurchaseTicketProps> = ({ eventId, tier }) => {
    const handlePurchase = async () => {
        try {
            // Connect wallet (Xellar Kit)
            const signer = await getSigner();
            
            // Call factory contract
            const factory = new ethers.Contract(FACTORY_ADDRESS, factoryABI, signer);
            const eventContract = await factory.getEventContract(eventId);
            
            // Purchase ticket (gasless)
            const event = new ethers.Contract(eventContract, eventABI, signer);
            const tx = await event.purchaseTicket(tier.id, quantity);
            
            // Show success message
            toast.success('Ticket purchased successfully!');
        } catch (error) {
            handleError(error);
        }
    };
};
```

### 3. Scanner Interface
```typescript
const ScannerApp: React.FC = () => {
    const [scanning, setScanning] = useState(false);
    const [staff, setStaff] = useState<StaffInfo | null>(null);
    
    const handleScan = async (tokenId: string) => {
        try {
            setScanning(true);
            
            // Parse token ID
            const parsedTokenId = parseInt(tokenId);
            
            // Get NFT contract
            const nftContract = new ethers.Contract(NFT_ADDRESS, nftABI, signer);
            
            // Verify ownership and status
            const owner = await nftContract.ownerOf(parsedTokenId);
            const status = await nftContract.getTicketStatus(parsedTokenId);
            
            if (status !== 'valid') {
                throw new Error('Ticket already used or invalid');
            }
            
            // Update status (gasless)
            const tx = await nftContract.updateStatus(parsedTokenId, 'used');
            
            // Show success
            setScanResult({
                success: true,
                tokenId: parsedTokenId,
                owner,
                transactionHash: tx.hash
            });
            
        } catch (error) {
            setScanResult({
                success: false,
                error: error.message
            });
        } finally {
            setScanning(false);
        }
    };
};
```

## Event Management

### 1. Event Creation
```typescript
const createEventAlgo1 = async (eventData: EventData) => {
    const factory = new ethers.Contract(FACTORY_ADDRESS, factoryABI, signer);
    
    const tx = await factory.createEvent(
        eventData.name,
        eventData.description,
        eventData.date,
        eventData.venue
    );
    
    const receipt = await tx.wait();
    const eventCreatedEvent = receipt.events?.find(e => e.event === 'EventCreated');
    
    return {
        eventId: eventCreatedEvent.args.eventId,
        contractAddress: eventCreatedEvent.args.eventContract
    };
};
```

### 2. Staff Management
```typescript
const addStaff = async (eventContract: string, staffAddress: string) => {
    const event = new ethers.Contract(eventContract, eventABI, signer);
    const tx = await event.addStaff(staffAddress);
    await tx.wait();
};

const removeStaff = async (eventContract: string, staffAddress: string) => {
    const event = new ethers.Contract(eventContract, eventABI, signer);
    const tx = await event.removeStaff(staffAddress);
    await tx.wait();
};
```

### 3. Event Cancellation & Refunds
```typescript
const cancelEvent = async (eventContract: string) => {
    const event = new ethers.Contract(eventContract, eventABI, signer);
    const tx = await event.cancelEvent();
    await tx.wait();
};

const claimRefund = async (tokenId: number) => {
    const nft = new ethers.Contract(NFT_ADDRESS, nftABI, signer);
    const tx = await nft.claimRefund(tokenId);
    await tx.wait();
};
```

## Development Roadmap

### Phase 1: Smart Contract Development (3 weeks)
- [ ] Develop EventFactoryAlgo1.sol contract
- [ ] Develop EventAlgo1.sol contract with ERC-2771 support
- [ ] Develop TicketNFTAlgo1.sol contract
- [ ] Implement token ID generation system
- [ ] Add event cancellation and refund mechanism
- [ ] Unit testing untuk all contracts
- [ ] Deploy ke Lisk Sepolia testnet

### Phase 2: Frontend Integration (3 weeks)
- [ ] Algorithm selection interface
- [ ] Purchase flow integration
- [ ] My tickets page dengan NFT display
- [ ] Organizer dashboard untuk event management
- [ ] Staff management interface
- [ ] Web-based scanner application

### Phase 3: Testing & Optimization (2 weeks)
- [ ] End-to-end testing complete flow
- [ ] Gas optimization untuk meta transactions
- [ ] Security testing
- [ ] Performance testing untuk concurrent users
- [ ] User acceptance testing

## Security Considerations

### 1. Smart Contract Security
- **Access Control**: Role-based permissions dengan modifier
- **Reentrancy Protection**: ReentrancyGuard untuk all state-changing functions
- **Meta Transaction Security**: Proper ERC-2771 implementation
- **Token ID Validation**: Prevent collision dan unauthorized generation

### 2. Frontend Security
- **Wallet Connection**: Secure wallet authentication
- **Input Validation**: Sanitize all user inputs
- **Error Handling**: Graceful error handling dan user feedback
- **Anti-Double Scan**: UI state management untuk prevent double scanning

### 3. Operational Security
- **Staff Authentication**: Wallet-based staff verification
- **Emergency Procedures**: Manual backup untuk internet outages
- **Event Cancellation**: Secure refund mechanism
- **Audit Trail**: All transactions recorded on blockchain

## Performance Targets

### 1. Technical Metrics
- **Transaction Success Rate**: >98%
- **Blockchain Response Time**: <30 seconds
- **Scanner App Performance**: <3 second load time
- **Concurrent Users**: Up to 500 simultaneous scans

### 2. User Experience
- **Purchase Flow**: <5 steps to complete
- **Wallet Integration**: <10 seconds connection time
- **QR Generation**: Instant (no network call)
- **Entry Process**: <60 seconds dari scan sampai entry

## Future Enhancements

### 1. Short Term (Phase 2)
- **Batch Operations**: Multiple ticket processing
- **Enhanced Analytics**: Real-time event statistics
- **Mobile Optimization**: Better mobile web experience
- **Multi-language Support**: Indonesian + English

### 2. Long Term (Phase 3+)
- **The Graph Indexer**: Fast query optimization
- **Advanced Role Management**: Granular staff permissions
- **Integration APIs**: Third-party event management integration
- **Cross-Chain Support**: Multi-blockchain deployment

## Conclusion
Algorithm 1 menyediakan foundation yang solid untuk pure Web3 ticketing system dengan fokus pada simplicity, security, dan user control. Dengan ERC-2771 meta transactions dan factory pattern, sistem ini optimal untuk organizer yang ingin memberikan authentic blockchain experience kepada attendees mereka sambil tetap maintaining ease of use.