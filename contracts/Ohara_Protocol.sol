// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:security-contact dodo920306@gmail.com
contract Ohara_Protocol is Initializable, ERC1155Upgradeable, AccessControlUpgradeable, PausableUpgradeable, ERC1155BurnableUpgradeable, ERC1155SupplyUpgradeable {
    address payable public gnosisSafeAddress; // The address of Ohara Protocol.
    uint16 public marketFeeRate; // The transaction fee got by Ohara Protocol every tx.
    uint256 public currentId; // Current Id of book that can be published.

    struct Listing {
        uint256 price; // 賣價掛單價格
        uint256 listedBalance; // 賣家上架的數量
    }

    struct Detail {
        bytes32 publisher;
        uint16 revenueFeeRates;
        address revenueReceiver;
        uint256 totalAmount;
    }
    
    mapping (uint256 => mapping (address => Listing)) public idToListings; // id => seller => Listing
    mapping (uint256 => Detail) public idToDetail; // id => Detail

    mapping (uint256 => string) public idToMetadataUrl;
    mapping (address => mapping (uint256 => string)) public userToBookKeySecret;

    event EBookListed(uint256 indexed id, uint256 indexed amount, uint256 indexed price, address seller);
    event PriceModified(uint256 indexed id, uint256 indexed originalPrice, uint256 indexed currentPrice, address seller);
    event ListingCancelled(uint256 indexed id, address indexed seller, uint256 indexed removeAmount);
    event TransactionMade(uint256 indexed id, address indexed seller, address buyer, uint256 indexed amount);

    modifier isIdExisted(uint256[] memory ids) {
        for (uint256 i = 0; i < ids.length; ++i) {
            require(ids[i] < currentId, "ERC1155: Requested id doesn't exist.");
        }
        _;
    }

    modifier isAmountValid(uint256 amount) {
        require(amount > 0, "Invalid price/amount");
        _;
    }

    modifier isAddressValid(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    modifier isEBookAvailable(uint256 id, address seller) {
        require(idToListings[id][seller].listedBalance > 0, "E-Book is not listed or sold out");
        _;
    }

    // There's no onlyPublisherSingle, for that it basically equals to onlyRole modifier from AccessControl. 
    modifier onlyPublisherBatch(uint256[] memory ids) {
        for (uint256 i = 0; i < ids.length; ++i) {
            _checkRole(idToDetail[ids[i]].publisher);
        }
        _;
    }

    modifier isBalanceValid(address from, uint256[] memory ids, uint256[] memory amounts) {
        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能轉移未上架的數量
            require(balanceOf(from, ids[i]) - idToListings[ids[i]][from].listedBalance >= amounts[i], "ERC1155: Insufficient balance to transfer and list");
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address payable _gnosisSafeAddr, uint16 _marketFeeRate) initializer public {
        __ERC1155_init("");
        __AccessControl_init();
        __Pausable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        gnosisSafeAddress = _gnosisSafeAddr;
        marketFeeRate = _marketFeeRate;
    }

    // Tim: added whenNotPaused
    function setURI(string memory newuri) public whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /**
     * @dev The publisher who wants to claim an account belongs to them must use this function
     * with the magic string that represents themselves.
     * 
     * The function will uses keccak256 solidity function to hash this string, but before that, it must be represented as bytes32.
     * The type conversion from "string memory" to "bytes32" isn't allowed, so we use abi.encode() here.
     * See https://ethereum.stackexchange.com/questions/119583/when-to-use-abi-encode-abi-encodepacked-or-abi-encodewithsignature-in-solidity
     * for the reason of this selection.
     * 
     * After that, we use grantRole() function from AccessControl,
     * the reason we don't directly use _grantRole() here is because the onlyRole(getRoleAdmin(role)) should also be passed in this operation,
     * and since grantRole() has that modifier originally, the current function doesn't require any modifier yet,
     * and there's no need to be afraid that anyone hash others' magic string and directly call grantRole() because there's no way he/she can be the admin.
     * 
     * If it's the first member to be added in the publisher,
     * the _msgSender() must be DEFAULT_ADMIN_ROLE to pass onlyRole(getRoleAdmin(role)) for that there's no way to set admin to others.
     * If so, then the function would call _setRoleAdmin() to release the admin power to the publisher itself,
     * indicating that from this point on, only the publisher can manage which accounts can act on its behalf.
     * 
     * The only risk would be that a hacker steal one private key from DEFAULT_ADMIN_ROLE,
     * in that case, the worse he/she can do is grant his/her accounts the publisher role that "hasn't been registered yet",
     * for that the admins of the publishers already in the protocol can only be themselves.
     * If so, then the publishers register in the future cannot use the same magic string as the hacker granted himself/herself even if they want.
     * (Basically, it's the same idea as "This username has already been used. Please try another.",
     * so the power of DEFAULT_ADMIN_ROLE is basically just register publishers and ids.)
     *
     */
    // Tim: added whenNotPaused
    function grantPublisher(string memory publisher, address account) public virtual whenNotPaused {
        bytes32 role = keccak256(abi.encode(publisher));
        grantRole(role, account);

        if (getRoleAdmin(role) == DEFAULT_ADMIN_ROLE) _setRoleAdmin(role, role);
    }

    /**
     * @dev See the comment of grantPublisher() above for more info about the string publisher and the bytes32 role.
     * This function is called when publishing books for transfering idToDetail[currentId].
     */
    // Tim: added whenNotPaused
    function setIdToDetail(string memory publisher, uint16 revenueRate, address revenueReceiver, uint256 amount)
        public
        whenNotPaused
        isAmountValid(amount)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(revenueRate + marketFeeRate <= 10000, "ERC1155: The sum of marketFeeRate and revenueRate should not exceed 100.00%");
        bytes32 role = keccak256(abi.encode(publisher));
        idToDetail[currentId++] = Detail({
            publisher: role,
            revenueFeeRates: revenueRate,
            revenueReceiver: revenueReceiver,
            totalAmount: amount
        });
    }

    /**
     * @dev See the comment of grantPublisher() above for more info about the string publisher and the bytes32 role.
     * The reason we don't directly call _revokeRole() and the this function is safe is the same reason grantPublisher() doesn't call _grantRole().
     * Use this function to kick someone including _msgSender() himself/herself out of the publisher.
     * The function also can only be called by the publisher itself.
     */
    // Tim: added whenNotPaused
    function revokePublisher(string memory publisher, address account) public virtual whenNotPaused {
        bytes32 role = keccak256(abi.encode(publisher));
        revokeRole(role, account);
    }

    // Tim: added two functions to call hasRole() & getRoleAdmin(), not sure if thye're needed
    // Kirin: They are not needed because they are just imported with AccessControlUpgradeable.

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // The publisher of the id would have power to mint the id to whoever they want.
    function mint(address to, uint256 id, uint256 amount, bytes memory data)
        public
        whenNotPaused
        isIdExisted(_asSingletonArray(id))
        onlyRole(idToDetail[id].publisher)
    {
        require(totalSupply(id) + amount <= idToDetail[id].totalAmount, "ERC1155: Mint amount exceeds.");
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        whenNotPaused
        isIdExisted(ids)
        onlyPublisherBatch(ids)
    {
        for (uint256 i = 0 ; i < ids.length ; ++i) {
            require(totalSupply(ids[i]) + amounts[i] <= idToDetail[ids[i]].totalAmount, "ERC1155: Mint amount exceeds.");
        }
        _mintBatch(to, ids, amounts, data);
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) public isBalanceValid(from, _asSingletonArray(id), _asSingletonArray(amount)) override(ERC1155Upgradeable) {
        super.safeTransferFrom(from, to, id, amount, data);
    }

    function safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public isBalanceValid(from, ids, amounts) override(ERC1155Upgradeable) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function changeMetadataUrl(uint256 id, string calldata newMetadataUrl) public onlyRole(DEFAULT_ADMIN_ROLE) {
        idToMetadataUrl[id] = newMetadataUrl;
    }

    function changeBookKeySecret(address user, uint256 id, string calldata key) public onlyRole(DEFAULT_ADMIN_ROLE) {
        userToBookKeySecret[user][id] = key;
    }

    // ----------------------- Market functions -----------------------
    // Tim: 上架電子書
    function listEBook(uint256 id, uint256 price, uint256 amount) public virtual whenNotPaused isIdExisted(_asSingletonArray(id)) isAddressValid(_msgSender()) isAmountValid(amount) isBalanceValid(_msgSender(), _asSingletonArray(id), _asSingletonArray(amount)) {
        idToListings[id][_msgSender()].price = price;

        idToListings[id][_msgSender()].listedBalance += amount;

        emit EBookListed(id, amount, price, _msgSender());
    }

    // Tim: 修改已上架的電子書的價格
    function modifyPrice(uint256 id, uint256 price) public virtual whenNotPaused isAddressValid(_msgSender()) isEBookAvailable(id, _msgSender()) {
        uint256 originalPrice = idToListings[id][_msgSender()].price;
        idToListings[id][_msgSender()].price = price;

        emit PriceModified (id, originalPrice, price, _msgSender());
    }

    // Tim: 下架電子書
    function cancelListing(uint256 id, uint256 amount) public virtual whenNotPaused isAmountValid(amount) isEBookAvailable(id, _msgSender()) {
        require(idToListings[id][_msgSender()].listedBalance >= amount, "ERC1155: Exceeded amount to unlist"); // 上架數量 >= 欲下架數量

        unchecked {
            idToListings[id][_msgSender()].listedBalance -= amount;
        }

        emit ListingCancelled(id, _msgSender(), amount);
    }

    // Tim: 購買電子書
    function purchaseEBook(uint256 id, address payable seller, uint256 amount) public payable virtual whenNotPaused isAmountValid(amount) isEBookAvailable(id, seller) {
        require(idToListings[id][seller].listedBalance >= amount, "ERC1155: Exceeded amount to unlist"); // 上架數量 >= 欲購買數量

        // 處理價格細項
        uint256 price = idToListings[id][seller].price * amount; // 電子書價格

        uint256 revenueFee = price * idToDetail[id].revenueFeeRates / 10000; // 出版商收益 = 電子書價格 * 收益費率 / 10000
        uint256 marketFee = price * marketFeeRate / 10000; // 手續費 = 電子書價格 * 手續費費率 / 10000

        uint256 total = price + revenueFee + marketFee; // 應付價格 = 電子書價格 + 出版商收益 + 手續費
        require(msg.value >= total, "Insufficient Ether");

        // 執行轉帳
        bool sent;
        _safeTransferFrom(seller, _msgSender(), id, amount, ""); // 轉移電子書給買家
        
        (sent, ) = seller.call{value: price}(""); // 轉移售價給賣家

        (sent, ) = gnosisSafeAddress.call{value: marketFee}(""); // 轉移手續費給多簽錢包

        address payable buyer = payable(_msgSender());
        address payable revenueReceiver = payable(idToDetail[id].revenueReceiver);
        (sent, ) = revenueReceiver.call{value: revenueFee}(""); // 轉移出版商收益給出版商

        if (msg.value - total > 0) (sent, ) = buyer.call{value: msg.value - total}(""); // 將剩餘 ETH 轉回給買家

        require(sent, "Transfer failed.");
        // 處理電子書掛單資訊
        idToListings[id][seller].listedBalance -= amount;

        emit TransactionMade(id, seller, buyer, amount);
    }

    receive() external payable {
        
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}