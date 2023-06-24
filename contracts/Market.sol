// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract Market is ERC1155Upgradeable, ERC1155SupplyUpgradeable, PausableUpgradeable, AccessControlUpgradeable {

    struct Listing {
        uint256 price;
        uint256 currentPosition;
        uint256 buyerCounts;
        address[] buyers;
    }
    
    mapping (uint256 => mapping (address => Listing)) listings; // id => seller => price & buyers
    mapping (uint256 => mapping(address => uint256)) listedBalance; // user balances that aren't listed for sale

    event EBookListed(uint256 indexed id, address indexed seller, uint256 indexed price, uint256 amount);
    event PriceModified(uint256 indexed id, address priceModifier, uint256 indexed originalPrice, uint256 indexed currentPrice);
    event ListingCancelled(uint256 indexed id, address indexed seller, address indexed canceller);
    event BuyerDetermined(uint256 indexed id, address indexed seller, address indexed buyer);
    event TransactionMade(address indexed seller, address indexed buyer, uint256 indexed id);

    constructor() {
        _disableInitializers();
    }

    modifier isIdExisted(uint256 id) {
        require(super.exists(id), "Invalid ID");
        _;
    }

    modifier isApproved(address seller) {
        require(super.isApprovedForAll(msg.sender, seller), "Unauthorized address");
        _;
    }

    modifier isAddressValid(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    modifier IsEBookAvailableOnOrder(uint256 id, address seller) {  // 只能修改已上架且還未賣完的電子書的價格，或是下架已上架且還未賣完的電子書
        require(listedBalance[id][seller] > 0, "E-Book not listed or sold out");
        _;
    }

    modifier IsBuyerDetermined(uint256 id, address seller) {  // 後端已匹配其中一位買家且已呼叫 determineBuyer，則不能再修改價格或是下架
        require(listings[id][seller].buyerCounts == 0, "Buyer has been determined");
        _;
    }

    function initialize() initializer internal {
        __ERC1155_init("");
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Tim: 在買家確認後，授權給合約轉移電子書給買家的權限(在 determineBuyer 中呼叫)
    function _grantApprovalToContract(address seller) private {
        super._setApprovalForAll(seller, address(this), true);
    }

    // Tim: 在買家完成交易後，取消合約的權限(在 purchaseEBook 中呼叫)
    function _revokeApprovalFromContract(address seller) private {
        super._setApprovalForAll(seller, address(this), false);
    }

    // Tim: 查看賣家某 ID 的已上架的數量
    function listedBalanceOf(uint256 id, address account) internal view virtual returns(uint256) {
        return listedBalance[id][account];
    }

    // Tim: 上架電子書
    function listEBook(uint256 id, address seller, uint256 price, uint256 amount) internal virtual isIdExisted(id) isAddressValid(seller) isApproved(seller) {
        require(price > 0, "Invalid price");
        require(amount > 0, "Invalid amount");
        require(balanceOf(seller, id) - listedBalance[id][seller] >= amount, "Insefficient unlisted balance to list"); // 只能上架還未上架的數量

        listings[id][seller].price = price;
        listedBalance[id][seller] += amount;

        emit EBookListed(id, seller, price, amount);
    }

    // Tim: 修改已上架的電子書的價格
    function modifyPrice(uint256 id, address seller, uint256 price) internal virtual isIdExisted(id) isAddressValid(seller) isApproved(seller) IsEBookAvailableOnOrder(id, seller) IsBuyerDetermined(id, seller) {
        require(price > 0, "Invalid price");

        uint256 originalPrice = listings[id][seller].price;
        listings[id][seller].price = price;

        emit PriceModified (id, msg.sender, originalPrice, price);
    }

    // Tim: 下架電子書
    function cancelListing(uint256 id, address seller, uint256 amount) internal virtual isIdExisted(id) isAddressValid(seller) isApproved(seller) IsEBookAvailableOnOrder(id, seller) IsBuyerDetermined(id, seller) {
        require(amount > 0, "Invalid amount");
        require(listedBalance[id][seller] >= amount, "Exceeded amount to be unlisted"); // 要下架的數量必須小於等於已上架的數量

        unchecked {
            listedBalance[id][seller] -= amount;
        }

        emit ListingCancelled(id, seller, msg.sender);
    }

    // Tim: 決定最終買家，限定後端呼叫
    function determineBuyer(address seller, address buyer, uint256 id) internal virtual onlyRole(DEFAULT_ADMIN_ROLE) isIdExisted(id) isAddressValid(seller) isAddressValid(buyer) {

        listings[id][seller].buyers.push(buyer);
        listings[id][seller].buyerCounts ++;
        
        _grantApprovalToContract(seller);

        emit BuyerDetermined(id, seller, buyer);
    }

    // Tim: 購買電子書，限定 buyers 內的買家呼叫
    function purchaseEBook(uint256 id, address seller) internal virtual isIdExisted(id) isAddressValid(seller) IsEBookAvailableOnOrder(id, seller) {

        uint256 currentPosition = listings[id][seller].currentPosition;
        address buyer = listings[id][seller].buyers[currentPosition];
        uint256 price = listings[id][seller].price;

        require(buyer != address(0));
        
        //uint256 fee = price * 25 / 1000;

        super.safeTransferFrom(seller, buyer, id, 0, ""); // transfer ebook to buyer
        listedBalance[id][seller] -= 1;

        (bool success, ) = seller.call{ value: price }(""); // transfer ether to seller
        require(success, "Buying failed");

        //(bool suucess, ) = multiSigWallet.call{ value: fee}("");
        //require(success, "Buying failed");

        _revokeApprovalFromContract(seller);
        
        listings[id][seller].buyers[currentPosition] = address(0);
        currentPosition ++;
        listings[id][seller].buyerCounts --;

        if (currentPosition == listings[id][seller].buyers.length) {
            delete listings[id][seller];
        } else {
            listings[id][seller].currentPosition = currentPosition;
        }

        emit TransactionMade(seller, buyer, id);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能轉移未上架的數量
            require(balanceOf(from, ids[i]) - listedBalance[ids[i]][from] >= amounts[i], "Insufficient balance to transfer");
        }
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
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