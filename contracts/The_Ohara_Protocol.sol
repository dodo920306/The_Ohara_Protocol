// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:security-contact dodo920306@gmail.com
contract The_Ohara_Protocol is Initializable, ERC1155Upgradeable, AccessControlUpgradeable, PausableUpgradeable, ERC1155BurnableUpgradeable, ERC1155SupplyUpgradeable {
    mapping (uint256 => bytes32) private _idToPublisher;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // There's no onlyPublisherSingle, for that it basically equals to onlyRole modifier from AccessControl. 
    modifier onlyPublisherBatch(uint256[] memory ids) {
        for (uint256 i = 0; i < ids.length; ++i) {
            _checkRole(_idToPublisher[ids[i]]);
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

    function setURI(string memory newuri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /**
     * @dev The publisher who wants to claim an account belongs to them must use this function
     * with the magic string that represents themselves.
     * The magic string should conform to the following format:
     * it must be in English,
     * all in uppercase,
     * and spaces should be replaced by underscores.
     * The content of the string can be arbitrary, but for convenience, it is recommended to use a meaningful publisher name.
     * For instance, the magic string for 誠品書店 would be ESLITE_BOOKSTORE.
     * 
     * The function will uses keccak256 solidity function to hash this string, but before that, it must be represented as bytes32.
     * The type conversion from "string memory" to "bytes32" isn't allowed, so we uses abi.encode() here.
     * See https://ethereum.stackexchange.com/questions/119583/when-to-use-abi-encode-abi-encodepacked-or-abi-encodewithsignature-in-solidity
     * for the reason of this selection.
     * 
     * After that, we use grantRole() function from AccessControl,
     * the reason we don't directly use _grantRole() here is because the onlyRole(getRoleAdmin(role)) should also be passed in this operation,
     * and since grantRole() has that modifier originally, the current function doesn't require any modifier yet.
     */
    function grantPublisher(string memory publisher, address account) public virtual {
        bytes32 role = keccak256(abi.encode(publisher));
        grantRole(role, account);
    }

    /**
     * @dev See the comment of grantPublisher() above for more info about the string publisher and the bytes32 role.
     * This function should be invoked after a publisher has registered (the default admin role for any role is DEFAULT_ADMIN_ROLE),
     * indicating that from this point on, only the publisher can manage which accounts can act on its behalf.
     * 
     * The current function doesn't require any modifier yet,
     * for that it simply sets the admin role for the role represented by the magic string to itself.
     * Even if someone naughty enters others' magic string to this function,
     * the worst he can do is setting the victims' admin role to the victims themselves, which isn't a significant concern.
     */
    function setRoleAdminAsPublisherItself(string memory publisher) public virtual {
        bytes32 role = keccak256(abi.encode(publisher));
        _setRoleAdmin(role, role);
    }

    /**
     * @dev See the comment of grantPublisher() above for more info about the string publisher and the bytes32 role.
     * Only the old publisher could set the publisher of an id to a new one.
     * Since the default publisher of the id is 0x00, the first publisher of the id must be set by the DEFAULT_ADMIN_ROLE.
     */
    function setIdToPublisher(uint256 id, string memory publisher)
        public
        onlyRole(_idToPublisher[id])
    {
        bytes32 role = keccak256(abi.encode(publisher));
        _idToPublisher[id] = role;
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
        onlyRole(_idToPublisher[id])
    {
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyPublisherBatch(ids)
    {
        _mintBatch(to, ids, amounts, data);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
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