// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Quyx is Ownable, ReentrancyGuard {
    using Strings for uint256;
    using SafeMath for uint256;

    uint256 private _totalCards;
    uint256 private _totalBids;
    bool public isPaused;

    event CardMinted(
        address indexed owner,
        uint256 indexed cardId,
        string tempToken,
        uint256 timestamp
    );

    event CardDeleted(uint256 indexed cardId, uint256 timestamp);

    event CardListedForSale(
        uint256 indexed cardId,
        uint256 indexed version,
        bool isAuction,
        uint256 listingPrice,
        uint256 maxNumberOfBids,
        uint256 end,
        uint256 timestamp
    );

    event CardUnlisted(uint256 indexed cardId, uint256 timestamp);

    event BidPlaced(
        address indexed from,
        uint256 indexed cardId,
        address referredBy,
        uint256 amount,
        uint256 timestamp
    );

    event CardSold(
        address indexed to,
        uint256 indexed cardId,
        uint256 timestamp
    );

    event CardSaleEnded(uint256 indexed cardId, uint256 timestamp);

    modifier whenNotPaused() {
        require(!isPaused, "Pausable: paused");
        _;
    }

    string public baseURL;

    address public protocolFeeWallet;
    uint256 public protocolFeePercent;
    uint256 public referralFeePercent;

    address public protocolServiceWallet;
    address public FALLBACK_REFERRAL_ADDRESS;
    uint256 public EXTRA_CARD_PRICE;
    uint256 public constant MAX_CARD_PER_ADDRESS = 3;

    struct ListedCard {
        uint256 cardId;
        address owner;
        bool isAuction;
        uint256 listingPrice;
        uint256 maxNumberOfBids;
        uint256 end;
        bool isActive;
        uint256 timestamp;
    }

    struct Bid {
        uint256 cardId;
        address owner;
        address referredBy;
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public restrictedBalance;
    // cardId -> version
    mapping(uint256 => uint256) public currentVersion;
    // cardId -> (version -> (address -> bidId))
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        private _userBidOnCard;
    // bidId -> bool
    mapping(uint256 => bool) private _isBidIdValid;
    // cardId -> (version -> address)
    mapping(uint256 => mapping(uint256 => address))
        private _highestBidderOnCard;
    // cardId -> (version -> Bids)
    mapping(uint256 => mapping(uint256 => Bid[])) private _bids;
    mapping(uint256 => bool) public isCardListed;
    // cardId -> ListedCard{...}
    mapping(uint256 => ListedCard) private _listedCards;
    mapping(address => uint256[]) private _cardsOf;
    mapping(uint256 => address) private _ownerOf;

    constructor(string memory _baseURL) Ownable(msg.sender) {
        isPaused = false;
        setBaseURI(_baseURL);
    }

    function setProtocolFeeWallet(address _feeWallet) public onlyOwner {
        protocolFeeWallet = _feeWallet;
    }

    function setProtocolServiceWallet(address _serviceWallet) public onlyOwner {
        protocolServiceWallet = _serviceWallet;
    }

    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        protocolFeePercent = _feePercent;
    }

    function setReferralFeePercent(uint256 _feePercent) public onlyOwner {
        referralFeePercent = _feePercent;
    }

    function setBaseURI(string memory _baseURL) public onlyOwner {
        baseURL = _baseURL;
    }

    function setExtraCardPrice(uint256 _price) public onlyOwner {
        EXTRA_CARD_PRICE = _price;
    }

    function setFallbackReferralAddress(address _destination) public onlyOwner {
        FALLBACK_REFERRAL_ADDRESS = _destination;
    }

    function pause() public onlyOwner {
        isPaused = true;
    }

    function unpause() public onlyOwner {
        isPaused = false;
    }

    function cardsOf(address owner) public view returns (uint256[] memory) {
        return _cardsOf[owner];
    }

    function spendingBalanceOf(address owner) public view returns (uint256) {
        return balanceOf[owner].sub(restrictedBalance[owner]);
    }

    function ownerOf(uint256 cardId) public view returns (address) {
        return _ownerOf[cardId];
    }

    function listedCard(uint256 cardId)
        public
        view
        returns (ListedCard memory)
    {
        _requireCardToBeOwned(cardId);

        return _listedCards[cardId];
    }

    function bids(uint256 cardId) public view returns (Bid[] memory) {
        return _bids[cardId][currentVersion[cardId]];
    }

    function highestBidder(uint256 cardId) public view returns (Bid memory) {
        uint256 bidId = _userBidOnCard[cardId][currentVersion[cardId]][
            _highestBidderOnCard[cardId][currentVersion[cardId]]
        ];

        if (_isBidIdValid[bidId]) {
            return _bids[cardId][currentVersion[cardId]][bidId];
        }

        return Bid(0, address(0), address(0), 0, block.timestamp);
    }

    function userBidOnCard(uint256 cardId, address user)
        public
        view
        returns (Bid memory)
    {
        uint256 bidId = _userBidOnCard[cardId][currentVersion[cardId]][user];
        if (_isBidIdValid[bidId])
            return _bids[cardId][currentVersion[cardId]][bidId];

        return Bid(0, address(0), address(0), 0, block.timestamp);
    }

    function _requireCardToBeOwned(uint256 cardId)
        internal
        view
        returns (address)
    {
        address owner = ownerOf(cardId);
        require(owner != address(0), "card does not exist");

        return owner;
    }

    function cardURL(uint256 cardId) public view returns (string memory) {
        _requireCardToBeOwned(cardId);

        return
            bytes(baseURL).length > 0
                ? string.concat(baseURL, cardId.toString())
                : "";
    }

    function newCard(string memory tempToken) public payable {
        require(msg.sender != address(0), "msg.sender is zero address");

        uint256 cardId = ++_totalCards;
        uint256 userCardsCount = _cardsOf[msg.sender].length;
        if (userCardsCount >= MAX_CARD_PER_ADDRESS) {
            require(msg.value >= EXTRA_CARD_PRICE);

            balanceOf[msg.sender] = balanceOf[msg.sender].add(
                msg.value.sub(EXTRA_CARD_PRICE)
            );

            _withdraw(protocolServiceWallet, EXTRA_CARD_PRICE);
        }

        _cardsOf[msg.sender].push(cardId);
        _ownerOf[cardId] = msg.sender;

        emit CardMinted(msg.sender, cardId, tempToken, block.timestamp);
    }

    function _removeCardIdFromAddress(uint256 cardId, address owner) internal {
        uint256[] storage cardIds = _cardsOf[owner];

        for (uint256 i = 0; i < cardIds.length; i++) {
            if (cardIds[i] == cardId) {
                cardIds[i] = cardIds[cardIds.length - 1];
                cardIds.pop();

                break;
            }
        }
    }

    function deleteCard(uint256 cardId) public {
        address _owner = _requireCardToBeOwned(cardId);

        require(!isCardListed[cardId], "cannot delete listed card");
        require(
            _owner == msg.sender || msg.sender == owner(),
            "cannot delete another user card"
        );

        _removeCardIdFromAddress(cardId, _owner);
        _ownerOf[cardId] = address(0);

        emit CardDeleted(cardId, block.timestamp);
    }

    function unlistCard(uint256 cardId) public {
        address _owner = _requireCardToBeOwned(cardId);
        require(_owner == msg.sender || msg.sender == owner(), "unauthorized");
        require(isCardListed[cardId], "card not listed");

        if (_listedCards[cardId].isAuction) {
            require(
                bids(cardId).length == 0,
                "cannot unlist a card that has bids"
            );
        }

        _listedCards[cardId].isActive = false;
        isCardListed[cardId] = false;

        emit CardUnlisted(cardId, block.timestamp);
    }

    function listCard(
        uint256 cardId,
        bool isAuction,
        uint256 listingPrice,
        uint256 maxNumberOfBids,
        uint256 end
    ) public {
        address _owner = _requireCardToBeOwned(cardId);

        require(_owner == msg.sender, "cannot delete another user card");
        if (isAuction) require(end <= block.timestamp, "unrealistic date");
        require(!isCardListed[cardId], "card already lsited");

        _listedCards[cardId] = ListedCard(
            cardId,
            _owner,
            isAuction,
            listingPrice,
            maxNumberOfBids,
            end,
            true,
            block.timestamp
        );

        isCardListed[cardId] = true;
        currentVersion[cardId] += 1;

        emit CardListedForSale(
            cardId,
            currentVersion[cardId],
            isAuction,
            listingPrice,
            maxNumberOfBids,
            end,
            block.timestamp
        );
    }

    function _tranferCardOwnership(uint256 cardId, address to) internal {
        address currentOwner = ownerOf(cardId);
        _removeCardIdFromAddress(cardId, currentOwner);

        _ownerOf[cardId] = to;
        _cardsOf[to].push(cardId);
    }

    function buyCard(uint256 cardId, address referral) public payable {
        require(msg.sender != address(0), "msg.sender is zero address");

        ListedCard memory Card = listedCard(cardId);
        require(Card.isActive, "card sold already");
        require(!Card.isAuction, "listed for auction");
        require(msg.value >= Card.listingPrice, "amount less than price");

        address referredBy = referral == address(0)
            ? FALLBACK_REFERRAL_ADDRESS
            : referral;

        uint256 protocolFee = (Card.listingPrice * protocolFeePercent) /
            1 ether;
        uint256 referralFee = (Card.listingPrice * referralFeePercent) /
            1 ether;

        balanceOf[msg.sender] = balanceOf[msg.sender].add(
            msg.value.sub(Card.listingPrice)
        );

        balanceOf[Card.owner] = balanceOf[Card.owner].add(
            Card.listingPrice.sub(protocolFee.add(referralFee))
        );

        balanceOf[referredBy] = balanceOf[referredBy].add(referralFee);
        Card.isActive = false;
        isCardListed[cardId] = false;
        _tranferCardOwnership(cardId, msg.sender);
        _withdraw(protocolFeeWallet, protocolFee);

        emit CardSold(msg.sender, cardId, block.timestamp);
    }

    function _endAuction(uint256 cardId) internal {
        address _highestBidder = _highestBidderOnCard[cardId][
            currentVersion[cardId]
        ];
        ListedCard memory Card = listedCard(cardId);

        if (_highestBidder != address(0)) {
            Bid memory bid = userBidOnCard(cardId, _highestBidder);

            uint256 protocolFee = (Card.listingPrice * protocolFeePercent) /
                1 ether;
            uint256 referralFee = (Card.listingPrice * referralFeePercent) /
                1 ether;

            restrictedBalance[_highestBidder] = restrictedBalance[
                _highestBidder
            ].sub(Card.listingPrice);

            balanceOf[Card.owner] = balanceOf[Card.owner].add(
                Card.listingPrice.sub(protocolFee.add(referralFee))
            );

            balanceOf[bid.referredBy] = balanceOf[bid.referredBy].add(
                referralFee
            );

            _tranferCardOwnership(cardId, _highestBidder);

            emit CardSold(msg.sender, cardId, block.timestamp);
        }

        unlistCard(cardId);
    }

    function placeBid(uint256 cardId, address referral) public payable {
        require(msg.sender != address(0), "msg.sender is zero address");

        ListedCard memory Card = listedCard(cardId);
        require(Card.isActive, "card sold already");
        require(Card.isAuction, "not listed for auction");
        require(msg.value >= Card.listingPrice, "amount less than price");
        require(Card.end > block.timestamp, "Auction has ended");
        require(
            Card.maxNumberOfBids <=
                _bids[cardId][currentVersion[cardId]].length,
            "max number of bids reached"
        );

        uint256 _bidId = _userBidOnCard[cardId][currentVersion[cardId]][
            msg.sender
        ];
        if (!_isBidIdValid[_bidId]) _bidId = ++_totalBids;
        Bid memory senderCurrentBid = _bids[cardId][currentVersion[cardId]][
            _bidId
        ];

        if (
            _highestBidderOnCard[cardId][currentVersion[cardId]] != address(0)
        ) {
            Bid memory bid = _bids[cardId][currentVersion[cardId]][
                _userBidOnCard[cardId][currentVersion[cardId]][
                    _highestBidderOnCard[cardId][currentVersion[cardId]]
                ]
            ];

            require(
                (msg.value.add(senderCurrentBid.amount)) > bid.amount,
                "bid lower than latest bid"
            );
        }

        address referredBy = referral == address(0)
            ? FALLBACK_REFERRAL_ADDRESS
            : referral;

        _highestBidderOnCard[cardId][currentVersion[cardId]] = msg.sender;
        restrictedBalance[msg.sender] = restrictedBalance[msg.sender].add(
            msg.value
        );

        balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);

        if (!_isBidIdValid[_bidId]) {
            _userBidOnCard[cardId][currentVersion[cardId]][msg.sender] = _bidId;
            _isBidIdValid[_bidId] = true;
        }

        _bids[cardId][currentVersion[cardId]][_bidId] = Bid(
            cardId,
            msg.sender,
            referredBy,
            msg.value.add(senderCurrentBid.amount),
            block.timestamp
        );

        if (
            _bids[cardId][currentVersion[cardId]].length == Card.maxNumberOfBids
        ) _endAuction(cardId);

        emit BidPlaced(
            msg.sender,
            cardId,
            referredBy,
            msg.value.add(senderCurrentBid.amount),
            block.timestamp
        );
    }

    function endAuction(uint256 cardId) public {
        require(listedCard(cardId).owner == msg.sender, "unauthorized");
        require(isCardListed[cardId], "card not listed");

        _endAuction(cardId);
    }

    function withdrawFromAuction(uint256 cardId) public {
        require(isCardListed[cardId], "card not listed");
        require(
            _highestBidderOnCard[cardId][currentVersion[cardId]] != msg.sender,
            "you as the highest bidder cannot withdraw funds"
        );
        require(
            _isBidIdValid[
                _userBidOnCard[cardId][currentVersion[cardId]][msg.sender]
            ],
            "you don't have a bid on card"
        );

        Bid memory bid = _bids[cardId][currentVersion[cardId]][
            _userBidOnCard[cardId][currentVersion[cardId]][msg.sender]
        ];
        restrictedBalance[msg.sender] = restrictedBalance[msg.sender].sub(
            bid.amount
        );
        balanceOf[msg.sender] = balanceOf[msg.sender].add(bid.amount);
    }

    function emergencyWithdrawal(address to, uint256 amount)
        public
        onlyOwner
        nonReentrant
    {
        _withdraw(to, amount);
    }

    function withdraw(uint256 amount) public whenNotPaused nonReentrant {
        require(msg.sender != address(0), "msg.sender is zero address");

        uint256 _balance = spendingBalanceOf(msg.sender);
        require(_balance >= amount, "Insufficient balance");

        balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
        _withdraw(msg.sender, amount);
    }

    function _withdraw(address to, uint256 amount) internal {
        if (isPaused) {
            require(
                msg.sender == owner() ||
                    to == protocolFeeWallet ||
                    to == protocolServiceWallet,
                "Withdrawals are currently paused"
            );
        }

        require(
            address(this).balance > amount,
            "Insufficient contract balance"
        );

        (bool success, ) = to.call{value: amount}("");
        require(success, "Unable to send funds");
    }

    receive() external payable {}
}
