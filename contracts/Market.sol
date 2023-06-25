// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/*import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";*/
import "../node_modules/@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "../node_modules/@openzeppelin/contracts/security/Pausable.sol";
import "../node_modules/@openzeppelin/contracts/access/AccessControl.sol";

contract Market is ERC1155, ERC1155Supply, Pausable, AccessControl {

    mapping (uint256 => bytes32) idToPublisher; // Anyone can check which publisher an id belongs to.
    mapping (string => bool) publisherHasMember;

    struct Listing {
        uint256 price; // 賣價掛單價格
        uint256 listedBalance; // 賣家上架的數量
        uint256 buyerCounts; // 當前已匹配，且還未購買的買家
        address[] buyers; // 已匹配的買家
    }
    
    mapping (uint256 => mapping (address => Listing)) listings; // id => seller => Listing

    address market;

    event EBookListed(uint256 indexed id, address indexed seller, uint256 indexed price, uint256 amount);
    event PriceModified(uint256 indexed id, address priceModifier, uint256 indexed originalPrice, uint256 indexed currentPrice);
    event ListingCancelled(uint256 indexed id, address indexed seller, address indexed canceller);
    event BuyerDetermined(uint256 indexed id, address indexed seller, address indexed buyer);
    event TransactionMade(address indexed seller, address indexed buyer, uint256 indexed id);

    constructor() ERC1155("") {
        //_disableInitializers();
    }

    modifier isIdExisted(uint256 id) {
        require(super.exists(id), "Invalid ID");
        _;
    }

    modifier IsPriceOrAmountValid(uint256 priceOrAmount) {
        require(priceOrAmount > 0, "Invalid price/amount");
        _;
    }

    modifier isApproved(address seller) {
        require(super.isApprovedForAll(msg.sender, seller), "Unauthorized");
        _;
    }

    modifier isAddressValid(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    modifier IsEBookAvailableOnOrder(uint256 id, address seller) {  // 只能修改/下架已上架的電子書的價格
        require(listings[id][seller].listedBalance > 0, "not listed or sold out");
        _;
    }

    modifier IsBuyerDetermined(uint256 id, address seller) {  // 後端已匹配其中一位買家且已呼叫 determineBuyer，則不能再修改價格或是下架
        require(listings[id][seller].buyerCounts == 0, "Buyer has determined");
        _;
    }

    /*function initialize() initializer internal {
        __ERC1155_init("");
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }*/

    function _grantApprovalToContract(address seller) private {
        super._setApprovalForAll(seller, address(this), true);
    }

    // Tim: 在買家完成交易後，取消合約的權限(在 purchaseEBook 中呼叫)
    function _revokeApprovalFromContract(address seller) private {
        super._setApprovalForAll(seller, address(this), false);
    }

    function checkIsBuyer(uint256 id, address seller, address buyer) public view returns (int256) {

        uint256 length = listings[id][seller].buyers.length;
        address[] memory buyers = listings[id][seller].buyers;
        
        for (uint256 i = 0 ; i < length ; ++i) {
            if (buyers[i] == buyer) {
                return int256(i);
            }
        }

        return -1;
    }

    // Tim: 查看賣家某 ID 的已上架的數量
    function listedBalanceOf(address account, uint256 id) public view virtual returns(uint256) {
        return listings[id][account].listedBalance;
    }

    // Tim: 上架電子書
    function listEBook(uint256 id, address seller, uint256 price, uint256 amount) public virtual whenNotPaused isIdExisted(id) IsPriceOrAmountValid(price) IsPriceOrAmountValid(amount) isAddressValid(seller) isApproved(seller) {
        require(balanceOf(seller, id) - listings[id][seller].listedBalance >= amount, "Insefficient balance to list"); // 總餘額 - 已上架的數量 >= 欲上架的數量

        listings[id][seller].price = price;
        listings[id][seller].listedBalance += amount;

        emit EBookListed(id, seller, price, amount);
    }

    // Tim: 修改已上架的電子書的價格
    function modifyPrice(uint256 id, address seller, uint256 price) public virtual whenNotPaused isIdExisted(id) IsPriceOrAmountValid(price) isAddressValid(seller) isApproved(seller) IsEBookAvailableOnOrder(id, seller) IsBuyerDetermined(id, seller) {

        uint256 originalPrice = listings[id][seller].price;
        listings[id][seller].price = price;

        emit PriceModified (id, msg.sender, originalPrice, price);
    }

    // Tim: 下架電子書
    function cancelListing(uint256 id, address seller, uint256 amount) public virtual whenNotPaused isIdExisted(id) IsPriceOrAmountValid(amount) isAddressValid(seller) isApproved(seller) IsEBookAvailableOnOrder(id, seller) IsBuyerDetermined(id, seller) {
        require(listings[id][seller].listedBalance >= amount, "Exceeded amount to unlist"); // 上架數量 >= 欲下架數量

        unchecked {
            listings[id][seller].listedBalance -= amount;
        }

        if (listings[id][seller].listedBalance == 0) {
            delete listings[id][seller];
        }

        emit ListingCancelled(id, seller, msg.sender);
    }

    // Tim: 決定最終買家，限定後端呼叫
    function determineBuyer(address seller, address buyer, uint256 id) public virtual whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) isIdExisted(id) isAddressValid(seller) isAddressValid(buyer) {
        require(listings[id][seller].listedBalance > listings[id][seller].buyerCounts, "Order all fulfilled"); // 已匹配所有買家

        listings[id][seller].buyers.push(buyer);
        listings[id][seller].buyerCounts ++;
        
        _grantApprovalToContract(seller);

        emit BuyerDetermined(id, seller, buyer);
    }

    // Tim: 購買電子書，限定 buyers 內的買家呼叫
    function purchaseEBook(uint256 id, address seller, int256 index) public virtual whenNotPaused isIdExisted(id) isAddressValid(seller) IsEBookAvailableOnOrder(id, seller) {

        address buyer = msg.sender;
        require(index != -1, "not buyer");

        uint256 price = listings[id][seller].price;
        
        uint256 fee = price * 25 / 1000;

        super.safeTransferFrom(seller, buyer, id, 0, ""); // transfer ebook to buyer

        (bool success, ) = seller.call{ value: price }(""); // transfer ether to seller
        require(success, "Buying failed");

        //(bool suucess, ) = multiSigWallet.call{ value: fee}("");
        //require(success, "Buying failed");

        _revokeApprovalFromContract(seller);

        listings[id][seller].listedBalance --;
        listings[id][seller].buyerCounts --;
        listings[id][seller].buyers[uint256(index)] = address(0);

        if (listings[id][seller].listedBalance == 0) {
            delete listings[id][seller];
        }

        emit TransactionMade(seller, buyer, id);
    }

    // -----------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155, ERC1155Supply)
    {
        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能轉移未上架的數量
            require(balanceOf(from, ids[i]) - listedBalanceOf(from, ids[i]) >= amounts[i], "Insufficient balance to transfer");
        }

        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}