// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "./Market.sol";

/// @custom:security-contact dodo920306@gmail.com
contract The_Ohara_Protocol is Initializable, ERC1155Upgradeable, AccessControlUpgradeable, PausableUpgradeable, ERC1155BurnableUpgradeable, ERC1155SupplyUpgradeable {
    
    mapping (uint256 => bytes32) idToPublisher; // Anyone can check which publisher an id belongs to.
    mapping (string => bool) publisherHasMember;

    struct Listing {
        uint256 price; // 賣價掛單價格
        uint256 listedBalance; // 賣家上架的數量
        uint256 buyerCounts; // 當前已匹配，且還未購買的買家
        address[] buyers; // 已匹配的買家
    }
    
    mapping (uint256 => mapping (address => Listing)) listings; // id => seller => Listing

    //event EBookListed(uint256 indexed id, address indexed seller, uint256 indexed price, uint256 amount);
    //event PriceModified(uint256 indexed id, address priceModifier, uint256 indexed originalPrice, uint256 indexed currentPrice);
    //event ListingCancelled(uint256 indexed id, address indexed seller, address indexed canceller);
    //event BuyerDetermined(uint256 indexed id, address indexed seller, address indexed buyer);
    //event TransactionMade(address indexed seller, address indexed buyer, uint256 indexed id);

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // There's no onlyPublisherSingle, for that it basically equals to onlyRole modifier from AccessControl. 
    modifier onlyPublisherBatch(uint256[] memory ids) {
        for (uint256 i = 0; i < ids.length; ++i) {
            _checkRole(idToPublisher[ids[i]]);
        }
        _;
    }

    function initialize() initializer public {
        __ERC1155_init("");
        __AccessControl_init();
        __Pausable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setURI(string memory newuri) public whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) { // Tim: added whenNotPaused
        _setURI(newuri);
    }

    // Tim: get the actual e-book uri, may require further modifications
    // Tim: using toString() for getURIOfId()
    using StringsUpgradeable for uint256;   
    function getURIOfId(uint256 id) public view returns(string memory) {
        return string.concat(super.uri(id), "/", id.toString());
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
     * the msg.sender must be DEFAULT_ADMIN_ROLE to pass onlyRole(getRoleAdmin(role)) for that there's no way to set admin to others.
     * If so, then the function would call _setRoleAdmin() to release the admin power to the publisher itself,
     * indicating that from this point on, only the publisher can manage which accounts can act on its behalf.
     * 
     * The only risk would be that a hacker steal one private key from DEFAULT_ADMIN_ROLE,
     * in that case, the worse he/she can do is grant his/her accounts the publisher role that "hasn't been registered yet",
     * for that the admins of the publishers already in the protocol can only be themselves.
     * If so, then the publishers register in the future cannot use the same magic string as the hacker granted himself/herself even if they want.
     * (Basically, it's the same idea as "This username has already been used. Please try another.",
     * so the power of DEFAULT_ADMIN_ROLE is basically just register publishers and ids.)
     */
    function grantPublisher(string memory publisher, address account) public virtual whenNotPaused { // Tim: added whenNotPaused
        bytes32 role = keccak256(abi.encode(publisher));
        grantRole(role, account);

        if (!publisherHasMember[publisher]) {
            publisherHasMember[publisher] = true;
            _setRoleAdmin(role, role);
        }
    }

    /**
     * @dev See the comment of grantPublisher() above for more info about the string publisher and the bytes32 role.
     * Only the old publisher could set the publisher of an id to a new one.
     * Since the default publisher of the id is 0x00, the first publisher of the id must be set by the DEFAULT_ADMIN_ROLE.
     */
    function setIdToPublisher(uint256 id, string memory publisher) //Tim: added whenNotPaused
        public
        whenNotPaused
        onlyRole(idToPublisher[id])
    {
        bytes32 role = keccak256(abi.encode(publisher));
        idToPublisher[id] = role;
    }

    // Tim: added idExists() to check if an id has existed
    function idExists(uint256 id) public view returns (bool) {
        return super.exists(id);
    }

    /**
     * @dev See the comment of grantPublisher() above for more info about the string publisher and the bytes32 role.
     * The reason we don't directly call _revokeRole() and the this function is safe is the same reason grantPublisher() doesn't call _grantRole().
     * Use this function to kick someone including msg.sender himself/herself out of the publisher.
     * The function also can only be called by the publisher itself.
     */
    function revokePublisher(string memory publisher, address account) public virtual whenNotPaused { // Tim: added whenNotPaused
        bytes32 role = keccak256(abi.encode(publisher));
        revokeRole(role, account);
    }

    // Tim: added two functions to call hasRole() & getRoleAdmin(), not sure if thye're needed
    function hasRole(string memory role, address account) public view returns(bool) {
        return super.hasRole(keccak256(abi.encode(role)), account);
    }

    function getRoleAdmin(string memory role) public view returns(bytes32) {
        return super.getRoleAdmin(keccak256(abi.encode(role)));
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // The publisher of the id would have power to mint the id to whoever they want.
    function mint(address to, uint256 id, uint256 amount, bytes memory data)
        public
        onlyRole(idToPublisher[id])
    {
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyPublisherBatch(ids)
    {
        _mintBatch(to, ids, amounts, data);
    }

    // Tim: added burn() & burnBatch()
    function burn(address from, uint256 id, uint256 amount) public override(ERC1155BurnableUpgradeable) {

        require(balanceOf(from, id) - listedBalanceOf(from, id) >= amount, "burn amount exceeds unlisted balance"); // 只能銷毀未上架的數量

        super.burn(from, id, amount);
    }

    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts) public override(ERC1155BurnableUpgradeable) {

        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能銷毀未上架的數量
            require(balanceOf(from, ids[i]) - listedBalanceOf(from, ids[i]) >= amounts[i], "burn amount exceeds unlisted balance");
        }

        super.burnBatch(from, ids, amounts);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能轉移未上架的數量
            require(balanceOf(from, ids[i]) - listedBalanceOf(from, ids[i]) >= amounts[i], "Insufficient balance to transfer");
        }
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    // Tim: added transfer() & transferBatch()
    function transfer(address from, address to, uint256 id, uint256 amount, bytes memory data) public {
        super.safeTransferFrom(from, to, id, amount, data);
    }

    function transferBatch(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    // Tim: added balanceOf() & balanceOfBatch()
    function balanceOf(address account, uint256 id) 
        public
        view
        virtual
        override(ERC1155Upgradeable)
        returns(uint256)
    {
        return super.balanceOf(account, id);
    }

    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        override(ERC1155Upgradeable)
        returns (uint256[] memory)
    {
        return super.balanceOfBatch(accounts, ids) ;
    }

    // Tim: added setApprovalForAll() & isApprovedForAll()
    function setApprovalForAll(address operator, bool approved) public override(ERC1155Upgradeable) {
        super.setApprovalForAll(operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view override(ERC1155Upgradeable) returns (bool) {
        return super.isApprovedForAll(account, operator);
    }

    // Tim: added getIdSupply()
    function getIdSupply(uint256 id) public view returns (uint256) {
        return super.totalSupply(id);
    }

    // Tim: 在買家確認後，授權給合約轉移電子書給買家的權限(在 determineBuyer 中呼叫)
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
    function listEBook(uint256 id, address seller, uint256 price, uint256 amount) public virtual isIdExisted(id) IsPriceOrAmountValid(price) IsPriceOrAmountValid(amount) isAddressValid(seller) isApproved(seller) {
        require(balanceOf(seller, id) - listings[id][seller].listedBalance >= amount, "Insefficient balance to list"); // 總餘額 - 已上架的數量 >= 欲上架的數量

        listings[id][seller].price = price;
        listings[id][seller].listedBalance += amount;

        //emit EBookListed(id, seller, price, amount);
    }

    // Tim: 修改已上架的電子書的價格
    function modifyPrice(uint256 id, address seller, uint256 price) public virtual isIdExisted(id) IsPriceOrAmountValid(price) isAddressValid(seller) isApproved(seller) IsEBookAvailableOnOrder(id, seller) IsBuyerDetermined(id, seller) {

        //uint256 originalPrice = listings[id][seller].price;
        listings[id][seller].price = price;

        //emit PriceModified (id, msg.sender, originalPrice, price);
    }

    // Tim: 下架電子書
    function cancelListing(uint256 id, address seller, uint256 amount) public virtual isIdExisted(id) IsPriceOrAmountValid(amount) isAddressValid(seller) isApproved(seller) IsEBookAvailableOnOrder(id, seller) IsBuyerDetermined(id, seller) {
        require(listings[id][seller].listedBalance >= amount, "Exceeded amount to unlist"); // 上架數量 >= 欲下架數量

        unchecked {
            listings[id][seller].listedBalance -= amount;
        }

        if (listings[id][seller].listedBalance == 0) {
            delete listings[id][seller];
        }

        //emit ListingCancelled(id, seller, msg.sender);
    }

    // Tim: 決定最終買家，限定後端呼叫
    function determineBuyer(address seller, address buyer, uint256 id) public virtual onlyRole(DEFAULT_ADMIN_ROLE) isIdExisted(id) isAddressValid(seller) isAddressValid(buyer) {
        require(listings[id][seller].listedBalance > listings[id][seller].buyerCounts, "Order all fulfilled"); // 已匹配所有買家

        listings[id][seller].buyers.push(buyer);
        listings[id][seller].buyerCounts ++;
        
        _grantApprovalToContract(seller);

        //emit BuyerDetermined(id, seller, buyer);
    }

    // Tim: 購買電子書，限定 buyers 內的買家呼叫
    function purchaseEBook(uint256 id, address seller) public virtual isIdExisted(id) isAddressValid(seller) IsEBookAvailableOnOrder(id, seller) {

        address buyer = msg.sender;
        int256 index = checkIsBuyer(id, seller, buyer);
        require(index != -1, "not buyer");

        uint256 price = listings[id][seller].price;
        
        //uint256 fee = price * 25 / 1000;

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

        //emit TransactionMade(seller, buyer, id);
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