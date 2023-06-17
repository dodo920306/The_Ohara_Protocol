// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import { SeaportInterface } from "./SeaportInterface.sol";
import "./ConsiderationStructs.sol";

/// @custom:security-contact dodo920306@gmail.com
contract The_Ohara_Protocol is Initializable, ERC1155Upgradeable, AccessControlUpgradeable, PausableUpgradeable, ERC1155BurnableUpgradeable, ERC1155SupplyUpgradeable {
    
    mapping (uint256 => bytes32) idToPublisher; // Anyone can check which publisher an id belongs to.
    mapping (string => bool) publisherHasMember;
    SeaportInterface seaport;

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

    function initialize(address seaportAddr) initializer public {
        __ERC1155_init("");
        __AccessControl_init();
        __Pausable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // Tim: create SeaportInterface instance
        seaport = SeaportInterface(seaportAddr);
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
    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        public
        onlyRole(idToPublisher[id])
    {
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyPublisherBatch(ids)
    {
        _mintBatch(to, ids, amounts, data);
    }

    // Tim: added burn() & burnBatch()
    function burn(address from, uint256 id, uint256 amount) public override(ERC1155BurnableUpgradeable) {
        super.burn(from, id, amount);
    }

    function burnBatch(address account, uint256[] memory ids, uint256[] memory amounts) public override(ERC1155BurnableUpgradeable) {
        super.burnBatch(account, ids, amounts);
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
        returns(uint256 balance)
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

    // Tim: added functions in SeaportInterface.sol, except fulfillBasicOrder(for ERC721), information, & name
    function fulfillOrder(Order memory order, bytes32 fulfillerConduitKey) public payable returns (bool fulfilled) {
        fulfilled = seaport.fulfillOrder(order, fulfillerConduitKey);
    }

    function callFulfillAdvancedOrder(AdvancedOrder calldata advancedOrder, CriteriaResolver[] calldata criteriaResolvers, bytes32 fulfillerConduitKey, address recipient)
        public
        payable
        returns (bool fulfilled)
    {
        fulfilled = seaport.fulfillAdvancedOrder(advancedOrder, criteriaResolvers, fulfillerConduitKey, recipient);
    }

    function callFulfillAvailableOrders(
            Order[] calldata orders,
            FulfillmentComponent[][] calldata offerFulfillments,
            FulfillmentComponent[][] calldata considerationFulfillments,
            bytes32 fulfillerConduitKey,
            uint256 maximumFulfilled
        ) 
        public
        payable
        returns (bool[] memory availableOrders, Execution[] memory executions)
    {
        (availableOrders, executions) = seaport.fulfillAvailableOrders(orders, offerFulfillments, considerationFulfillments, fulfillerConduitKey, maximumFulfilled);
    }

    function callFulfillAvailableAdvancedOrders(
            AdvancedOrder[] calldata advancedOrders,
            CriteriaResolver[] calldata criteriaResolvers,
            FulfillmentComponent[][] calldata offerFulfillments,
            FulfillmentComponent[][] calldata considerationFulfillments,
            bytes32 fulfillerConduitKey,
            address recipient,
            uint256 maximumFulfilled
        )
        public
        payable
        returns (bool[] memory availableOrders, Execution[] memory executions)
    {
        (availableOrders, executions) = seaport.fulfillAvailableAdvancedOrders(advancedOrders, criteriaResolvers, offerFulfillments, considerationFulfillments, fulfillerConduitKey, recipient, maximumFulfilled);
    }

    function callMatchOrders(Order[] calldata orders, Fulfillment[] calldata fulfillments) external payable returns (Execution[] memory executions) {
        executions = seaport.matchOrders(orders, fulfillments);
    }

    function callMatchAdvancedOrders(AdvancedOrder[] calldata orders, CriteriaResolver[] calldata criteriaResolvers, Fulfillment[] calldata fulfillments, address recipient)
        public
        payable
        returns (Execution[] memory executions)
    {
        executions = seaport.matchAdvancedOrders(orders, criteriaResolvers, fulfillments, recipient);
    }

    function allCancel(OrderComponents[] calldata orders) public returns (bool cancelled) {
        cancelled = seaport.cancel(orders);
    }

    function callValidate(Order[] calldata orders) public returns (bool validated) {
        validated = seaport.validate(orders);
    }

    function callIncrementCounter() public returns (uint256 newCounter) {
        newCounter = seaport.incrementCounter();
    }

    function callGetOrderHash(OrderComponents calldata order) public view returns (bytes32 orderHash) {
        orderHash = seaport.getOrderHash(order);
    }

    function callGetOrderStatus(bytes32 orderHash) public view returns (bool isValidated, bool isCancelled, uint256 totalFilled, uint256 totalSize) {
        (isValidated, isCancelled, totalFilled, totalSize) = seaport.getOrderStatus(orderHash);
    }

    function callGetCounter(address offerer) public view returns (uint256 counter) {
        counter = seaport.getCounter(offerer);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}