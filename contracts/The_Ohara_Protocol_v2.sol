// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:security-contact dodo920306@gmail.com
contract The_Ohara_Protocol_v2 is Initializable, ERC1155Upgradeable, AccessControlUpgradeable, PausableUpgradeable, ERC1155BurnableUpgradeable, ERC1155SupplyUpgradeable {
    
    mapping (uint256 => bytes32) public idToPublisher; // Anyone can check which publisher an id belongs to.
    mapping (string => bool) public publisherHasMember;

    struct Listing {
        uint256 price; // 賣價掛單價格
        uint256 listedBalance; // 賣家上架的數量
        uint256 buyerCounts; // 當前已匹配，且還未購買的買家
        address[] buyers; // 已匹配的買家
    }

    struct RevenueFeeInfo {
        uint256 revenueFeeRate; // 出版商收益比率
        address publisher; // 負責收取收益，為呼叫 mint 的出版商帳號
    }
    
    mapping (uint256 => mapping (address => Listing)) public listings; // id => seller => Listing
    mapping (uint256 => RevenueFeeInfo) public publisherRevenueFeeRates; // id => revenue percentage

    address payable gnosisSafeAddress;
    uint16 marketFeeRate = 25;
    uint256 public currentId;

    mapping (uint256 => string) public idToMetadataUrl;
    mapping (address => mapping (uint256 => string)) public userToBookKeySecret;

    event EBookListed(uint256 indexed id, uint256 indexed amount, uint256 indexed price, address seller);
    event PriceModified(uint256 indexed id, uint256 indexed originalPrice, uint256 indexed currentPrice, address seller, address priceModifier);
    event ListingCancelled(uint256 indexed id, address indexed seller, uint256 indexed removeAmount, address canceller);
    event BuyerDetermined(uint256 indexed id, address indexed seller, address indexed buyer);
    event TransactionMade(uint256 indexed id, address indexed seller, address indexed buyer);

    modifier isIdExisted(uint256 id) {
        require(super.exists(id), "Invalid ID");
        _;
    }

    modifier IsPriceOrAmountValid(uint256 priceOrAmount) {
        require(priceOrAmount > 0, "Invalid price/amount");
        _;
    }

    modifier isApproved(address seller) {
        require(super.isApprovedForAll(msg.sender, seller) || seller == msg.sender, "Unauthorized account");
        _;
    }

    modifier isAddressValid(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    // 只能修改/下架已上架的電子書的價格
    modifier IsEBookAvailableOnOrder(uint256 id, address seller) {
        require(listings[id][seller].listedBalance > 0, "E-Book is not listed or sold out");
        _;
    }

    // There's no onlyPublisherSingle, for that it basically equals to onlyRole modifier from AccessControl. 
    modifier onlyPublisherBatch(uint256[] memory ids) {
        for (uint256 i = 0; i < ids.length; ++i) {
            _checkRole(idToPublisher[ids[i]]);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address payable gnosisSafeAddr) initializer public {
        __ERC1155_init("");
        __AccessControl_init();
        __Pausable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        gnosisSafeAddress = gnosisSafeAddr;
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
    // Tim: added whenNotPaused
    function grantPublisher(string memory publisher, address account) public virtual whenNotPaused {
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
    // Tim: added whenNotPaused
    function setIdToPublisher(uint256 id, string memory publisher)
        public
        whenNotPaused
        onlyRole(idToPublisher[id])
    {
        require(id <= currentId, "ERC1155: Requested id greater than current id.");
        bytes32 role = keccak256(abi.encode(publisher));
        if(id == currentId) currentId++;
        idToPublisher[id] = role;
    }

    /**
     * @dev See the comment of grantPublisher() above for more info about the string publisher and the bytes32 role.
     * The reason we don't directly call _revokeRole() and the this function is safe is the same reason grantPublisher() doesn't call _grantRole().
     * Use this function to kick someone including msg.sender himself/herself out of the publisher.
     * The function also can only be called by the publisher itself.
     */
    // Tim: added whenNotPaused
    function revokePublisher(string memory publisher, address account) public virtual whenNotPaused {
        bytes32 role = keccak256(abi.encode(publisher));
        revokeRole(role, account);
    }

    // Tim: added two functions to call hasRole() & getRoleAdmin(), not sure if thye're needed
    // Kirin: They are not needed because they are just imported with AccessControlUpgradeable.sol.

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // The publisher of the id would have power to mint the id to whoever they want.
    function mint(address to, uint256 id, uint256 amount, bytes memory data, uint256 revenueRate)
        public
        whenNotPaused
        onlyRole(idToPublisher[id])
    {
        require(id < currentId, "ERC1155: Requested id doesn't exist.");
        publisherRevenueFeeRates[id].revenueFeeRate = revenueRate;
        publisherRevenueFeeRates[id].publisher = msg.sender;
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data, uint256[] memory revenueFeeRates)
        public
        whenNotPaused
        onlyPublisherBatch(ids)
    {
        require(revenueFeeRates.length == ids.length && revenueFeeRates.length == amounts.length, "ERC1155: revenues and ids/amounts length mismatch");
        for (uint256 i = 0 ; i < ids.length ; ++i) {
            publisherRevenueFeeRates[ids[i]].revenueFeeRate = revenueFeeRates[i];
            publisherRevenueFeeRates[ids[i]].publisher = msg.sender;
        }
        _mintBatch(to, ids, amounts, data);
    }

    // Tim: added burn() & burnBatch()
    function burn(address from, uint256 id, uint256 amount) public override(ERC1155BurnableUpgradeable) whenNotPaused {

        require(balanceOf(from, id) - listedBalanceOf(from, id) >= amount); // 只能銷毀未上架的數量

        super.burn(from, id, amount);
    }

    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts) public override(ERC1155BurnableUpgradeable) whenNotPaused {

        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能銷毀未上架的數量
            require(balanceOf(from, ids[i]) - listedBalanceOf(from, ids[i]) >= amounts[i]);
        }

        super.burnBatch(from, ids, amounts);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    // Tim: added transfer() & transferBatch()
    function transfer(address from, address to, uint256 id, uint256 amount, bytes memory data) public {
        require(balanceOf(from, id) - listedBalanceOf(from, id) >= amount, "Insufficient balance to transfer");// 只能轉移未上架的數量
        super.safeTransferFrom(from, to, id, amount, data);
    }

    function transferBatch(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public {
        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能轉移未上架的數量
            require(balanceOf(from, ids[i]) - listedBalanceOf(from, ids[i]) >= amounts[i], "Insufficient balance to transfer");
        }
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
    function setApprovalForAll(address operator, bool approved) public override(ERC1155Upgradeable) whenNotPaused {
        super.setApprovalForAll(operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view override(ERC1155Upgradeable) returns (bool) {
        return super.isApprovedForAll(account, operator);
    }

    // Tim: added getIdSupply()
    function getIdSupply(uint256 id) public view returns (uint256) {
        return super.totalSupply(id);
    }

    function changeMetadataUrl(uint256 id, string calldata newMetadataUrl) public onlyRole(DEFAULT_ADMIN_ROLE) {
        idToMetadataUrl[id] = newMetadataUrl;
    }

    function changeBookKeySecret(address user, uint256 id, string calldata key) public onlyRole(DEFAULT_ADMIN_ROLE) {
        userToBookKeySecret[user][id] = key;
    }

    // ----------------------- below are market functions -----------------------
/*
    function checkIsBuyer(uint256 id, address seller, address buyer) public returns (int256) {
        (bool ok, bytes memory data) = market.delegatecall(
            abi.encodeWithSignature("checkIsBuyer(uint256,address,address)", id, seller, buyer)
        );
        require(ok);
        return abi.decode(data, (int256));
    }

    // Tim: 查看賣家某 ID 的已上架的數量
    function listedBalanceOf(address account, uint256 id) public view returns(uint256) {
        return listings[id][account].listedBalance;
    }

    // Tim: 上架電子書
    function listEBook(uint256 id, address seller, uint256 price, uint256 amount) public {
        (bool ok, ) = market.delegatecall(
            abi.encodeWithSignature("listEBook(uint256,address,uint256,uint256)", id, seller, price, amount)
        );
        require(ok);
    }

    // Tim: 修改已上架的電子書的價格
    function modifyPrice(uint256 id, address seller, uint256 price) public {
        (bool ok, ) = market.delegatecall(
            abi.encodeWithSignature("modifyPrice(uint256,address,uint256)", id, seller, price)
        );
        require(ok);
    }

    // Tim: 下架電子書
    function cancelListing(uint256 id, address seller, uint256 amount) public {
        (bool ok, ) = market.delegatecall(
            abi.encodeWithSignature("cancelListing(uint256,address,uint256)", id, seller, amount)
        );
        require(ok);
    }

    // Tim: 決定最終買家，限定後端呼叫
    function determineBuyer(address seller, address buyer, uint256 id) public onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool ok, ) = market.delegatecall(
            abi.encodeWithSignature("cancelListing(address,address,uint256)", seller, buyer, id)
        );
        require(ok);
    }

    // Tim: 購買電子書，限定 buyers 內的買家呼叫
    function purchaseEBook(uint256 id, address seller) public payable {
        int256 index = checkIsBuyer(id, seller, msg.sender);
        (bool ok, ) = market.delegatecall(
            abi.encodeWithSignature("purchaseEBook(uint256,address,int256)", id, seller, index)
        );
        require(ok);
    }
*/
    function changeMarketFee(uint16 newMarketFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        marketFeeRate = newMarketFee;
    }

    function changeGnosisSafeAddress(address payable newAddr) public onlyRole(DEFAULT_ADMIN_ROLE) {
        gnosisSafeAddress = newAddr;
    }

    //  Tim: 在確認買家後，授權合約的權限(在 determineBuyer 中呼叫)
    function _grantApprovalToContract(address seller) private {
        super._setApprovalForAll(seller, address(this), true);
    }

    // Tim: 在買家完成交易後，取消合約的權限(在 purchaseEBook 中呼叫)
    function _revokeApprovalFromContract(address seller) private {
        super._setApprovalForAll(seller, address(this), false);
    }

    // Tim: 檢查是否為買家
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

    // Tim: 查看賣家某 ID 的上架價格
    function getPrice(uint256 id, address seller) public view returns (uint256) {
        return listings[id][seller].price;
    }

    // Tim: 上架電子書
    function listEBook(uint256 id, address seller, uint256 price, uint256 amount) public virtual whenNotPaused isIdExisted(id) IsPriceOrAmountValid(price) IsPriceOrAmountValid(amount) isAddressValid(seller) isApproved(seller) {
        require(balanceOf(seller, id) - listings[id][seller].listedBalance >= amount, "Insefficient balance to list"); // 總餘額 - 已上架的數量 >= 欲上架的數量

        if (listings[id][seller].buyerCounts == 0) {
            listings[id][seller].price = price;
        }

        listings[id][seller].listedBalance += amount;

        emit EBookListed(id, amount, price, seller);
    }

    // Tim: 修改已上架的電子書的價格
    function modifyPrice(uint256 id, address seller, uint256 price) public virtual whenNotPaused isIdExisted(id) IsPriceOrAmountValid(price) isAddressValid(seller) isApproved(seller) IsEBookAvailableOnOrder(id, seller) {
        require(listings[id][seller].buyerCounts == 0, "Buyer has determined"); // 後端已匹配其中一位買家且已呼叫 determineBuyer，則不能再修改價格

        uint256 originalPrice = listings[id][seller].price;
        listings[id][seller].price = price;

        emit PriceModified (id, originalPrice, price, seller, msg.sender);
    }

    // Tim: 下架電子書
    function cancelListing(uint256 id, address seller, uint256 amount) public virtual whenNotPaused isIdExisted(id) IsPriceOrAmountValid(amount) isAddressValid(seller) isApproved(seller) IsEBookAvailableOnOrder(id, seller) {
        require(listings[id][seller].listedBalance - listings[id][seller].buyerCounts >= amount, "Exceeded amount to unlist"); // 上架且尚未匹配數量 >= 欲下架數量

        unchecked {
            listings[id][seller].listedBalance -= amount;
        }

        if (listings[id][seller].listedBalance == 0) {
            delete listings[id][seller];
        }

        emit ListingCancelled(id, seller, amount, msg.sender);
    }

    // Tim: 決定最終買家，限定後端呼叫
    function determineBuyer(address seller, address buyer, uint256 id) public virtual whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) isIdExisted(id) isAddressValid(seller) isAddressValid(buyer) {
        require(listings[id][seller].listedBalance > listings[id][seller].buyerCounts, "Order all fulfilled"); // 上架的每一本都已匹配買家

        listings[id][seller].buyers.push(buyer);
        
        if (listings[id][seller].buyerCounts == 0) { // 如果是第一個匹配的，才呼叫授權
            _grantApprovalToContract(seller);
        }

        listings[id][seller].buyerCounts ++;

        emit BuyerDetermined(id, seller, buyer);
    }

    // Tim: 購買電子書，限定 buyers 內的買家呼叫
    function purchaseEBook(uint256 id, address payable seller) public payable virtual whenNotPaused isIdExisted(id) isAddressValid(seller) IsEBookAvailableOnOrder(id, seller) {
        
        // 確認呼叫者是否為買家
        address payable buyer = payable(msg.sender);
        int256 index = checkIsBuyer(id, seller, buyer);
        require(index != -1, "not buyer");

        // 處理價格細項
        uint256 price = listings[id][seller].price; // 電子書價格

        uint256 publisherRevenueFee = price * publisherRevenueFeeRates[id].revenueFeeRate / 1000; // 出版商收益 = 電子書價格 * 出版商收益費率 / 1000
        uint256 marketFee = price * marketFeeRate / 1000; // 手續費 = 電子書價格 * 手續費費率 / 1000

        uint256 total = price + publisherRevenueFee + marketFee; // 應付價格 = 電子書價格 + 出版商收益 + 手續費
        require(msg.value >= total, "Insufficient Ether");

        // 執行轉帳
        super._safeTransferFrom(seller, buyer, id, 1, ""); // 轉移電子書給買家
        
        seller.transfer(price); // 轉移售價給賣家

        gnosisSafeAddress.transfer(marketFee); // 轉移手續費給多簽錢包

        address payable publisher = payable(publisherRevenueFeeRates[id].publisher);
        publisher.transfer(publisherRevenueFee); // 轉移出版商收益給出版商

        if (msg.value - total > 0) { // 將剩餘 ETH 轉回給買家
            buyer.transfer(msg.value - total);
        }

        // 處理電子書掛單資訊
        listings[id][seller].listedBalance --;
        listings[id][seller].buyerCounts --;
        listings[id][seller].buyers[uint256(index)] = address(0);

        if (listings[id][seller].buyerCounts == 0) { // 當前已匹配的買家都已經完成交易
            _revokeApprovalFromContract(seller);
        }

        if (listings[id][seller].listedBalance == 0) { // 掛單全部買完
            delete listings[id][seller];
        }

        emit TransactionMade(id, seller, buyer);
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