// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/*import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";*/
import "../node_modules/@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "../node_modules/@openzeppelin/contracts/security/Pausable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "../node_modules/@openzeppelin/contracts/utils/Strings.sol";
import "./Market.sol";

/// @custom:security-contact dodo920306@gmail.com
contract The_Ohara_Protocol is ERC1155, AccessControl, Pausable, ERC1155Burnable, ERC1155Supply {
    
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address addr) ERC1155("") {
        market = addr;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        //_disableInitializers();
    }

    // There's no onlyPublisherSingle, for that it basically equals to onlyRole modifier from AccessControl. 
    modifier onlyPublisherBatch(uint256[] memory ids) {
        for (uint256 i = 0; i < ids.length; ++i) {
            _checkRole(idToPublisher[ids[i]]);
        }
        _;
    }

    /*function initialize(address addr) initializer public {
        __ERC1155_init("");
        __AccessControl_init();
        __Pausable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
    }*/

    function setURI(string memory newuri) public whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) { // Tim: added whenNotPaused
        _setURI(newuri);
    }

    // Tim: get the actual e-book uri, may require further modifications
    // Tim: using toString() for getURIOfId()
    using Strings for uint256;   
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
    /*function hasRole(string memory role, address account) public view returns(bool) {
        return super.hasRole(keccak256(abi.encode(role)), account);
    }

    function getRoleAdmin(string memory role) public view returns(bytes32) {
        return super.getRoleAdmin(keccak256(abi.encode(role)));
    }*/

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
        onlyRole(idToPublisher[id])
    {
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        whenNotPaused
        onlyPublisherBatch(ids)
    {
        _mintBatch(to, ids, amounts, data);
    }

    // Tim: added burn() & burnBatch()
    function burn(address from, uint256 id, uint256 amount) public override(ERC1155Burnable) whenNotPaused {

        require(balanceOf(from, id) - listedBalanceOf(from, id) >= amount); // 只能銷毀未上架的數量

        super.burn(from, id, amount);
    }

    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts) public override(ERC1155Burnable) whenNotPaused {

        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能銷毀未上架的數量
            require(balanceOf(from, ids[i]) - listedBalanceOf(from, ids[i]) >= amounts[i]);
        }

        super.burnBatch(from, ids, amounts);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155, ERC1155Supply)
    {
        for (uint256 i = 0 ; i < ids.length ; ++i) { // 只能轉移未上架的數量
            require(balanceOf(from, ids[i]) - listedBalanceOf(from, ids[i]) >= amounts[i]);
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
        override(ERC1155)
        returns(uint256)
    {
        return super.balanceOf(account, id);
    }

    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        override(ERC1155)
        returns (uint256[] memory)
    {
        return super.balanceOfBatch(accounts, ids) ;
    }

    // Tim: added setApprovalForAll() & isApprovedForAll()
    function setApprovalForAll(address operator, bool approved) public override(ERC1155) whenNotPaused {
        super.setApprovalForAll(operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view override(ERC1155) returns (bool) {
        return super.isApprovedForAll(account, operator);
    }

    // Tim: added getIdSupply()
    function getIdSupply(uint256 id) public view returns (uint256) {
        return super.totalSupply(id);
    }

    function changeMarketAddr(address newAddr) public onlyRole(DEFAULT_ADMIN_ROLE) {
        market = newAddr;
    }

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
    function purchaseEBook(uint256 id, address seller) public {
        int256 index = checkIsBuyer(id, seller, msg.sender);
        (bool ok, ) = market.delegatecall(
            abi.encodeWithSignature("purchaseEBook(uint256,address,int256)", id, seller, index)
        );
        require(ok);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}