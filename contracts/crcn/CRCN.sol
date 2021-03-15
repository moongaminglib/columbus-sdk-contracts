// SPDX-License-Identifier: MIT
pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/ownership/Ownable.sol";

import "../ERC1155/ERC1155.sol";
import "../ERC1155/ERC1155Metadata.sol";
import "../ERC1155/ERC1155MintBurn.sol";

import "./Strings.sol";

contract CRCN is ERC1155, ERC1155MintBurn, ERC1155Metadata, Ownable {
    using Strings for string;

    uint256 private _currentTokenID = 0;

    mapping(uint256 => address) public creators;

    mapping(uint256 => uint256) public tokenSupply;

    // ID => token cap, if a token cap is set to zero, then there is no token cap
    mapping(uint256 => uint256) public caps;

    mapping(uint256 => bool) private reservedId;

    // ID => uri
    string public _uri;

    struct Uint256Set {
        // Storage of set values
        uint256[] _values;
        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping(uint256 => uint256) _indexes;
    }

    struct AddressSet {
        // Storage of set values
        address[] _values;
        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping(address => uint256) _indexes;
    }

    // holder address => their (enumerable) set of owned tokens
    mapping(address => Uint256Set) private holderTokens;
    mapping(uint256 => AddressSet) private owners;

    // Contract name
    string public name;
    // Contract symbol
    string public symbol;

    /**
     * @dev Require msg.sender to be the creator of the token id
     */
    modifier creatorOnly(uint256 _id) {
        require(creators[_id] == msg.sender, "CRCN: ONLY_CREATOR_ALLOWED");
        _;
    }

    /**
     * @dev Require msg.sender to own more than 0 of the token id
     */
    modifier ownersOnly(uint256 _id) {
        require(isTokenOwner(msg.sender, _id), "CRCN: ONLY_OWNERS_ALLOWED");
        _;
    }

    constructor(string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
        _uri = ".json";
    }

    function totalSupply(uint256 _id) public view returns (uint256) {
        return tokenSupply[_id];
    }

    function addReservedAddress(uint256[] calldata _ids) external onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            reservedId[_ids[i]] = true;
        }
    }

    function removeReservedAddress(uint256[] calldata _ids) external onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            delete reservedId[_ids[i]];
        }
    }

    function tokensOf(address owner) public view returns (uint256[] memory) {
        return holderTokens[owner]._values;
    }

    function getNextTokenID() public view returns (uint256) {
        uint256 _id = _currentTokenID.add(1);
        if (reservedId[_id]) {
            return _id.add(1);
        }
        return _id;
    }

    function setUriEnd(string calldata __uri) external onlyOwner {
        _uri = __uri;
    }

    function getCurrentTokenID() external view returns (uint256) {
        return _currentTokenID;
    }

    function setCurrentTokenID(uint256 _tokenId) external onlyOwner {
        _currentTokenID = _tokenId;
    }

    /**
     * @dev Will update the base URL of token's URI
     * @param _newBaseMetadataURI New base URL of token's URI
     */
    function setBaseMetadataURI(string memory _newBaseMetadataURI)
        public
        onlyOwner
    {
        _setBaseMetadataURI(_newBaseMetadataURI);
    }

    function create(
        address _initialOwner,
        uint256 _initialSupply,
        uint256 _cap,
        bytes memory _data
    ) internal returns (uint256) {
        uint256 _id = _getNextTokenID();
        require(!_exists(_id), "ERC1155Tradable#create: NONEXISTENT_TOKEN");
        _currentTokenID = _id;
        creators[_id] = msg.sender;
        setAdd(_initialOwner, _id);
        _mint(_initialOwner, _id, _initialSupply, _data);
        tokenSupply[_id] = _initialSupply;
        caps[_id] = _cap;

        return _id;
    }

    function createWithId(
        address _initialOwner,
        uint256 _id,
        uint256 _initialSupply,
        uint256 _cap,
        bytes memory _data
    ) internal returns (uint256) {
        require(!_exists(_id), "ERC1155Tradable#create: NONEXISTENT_TOKEN");
        require(
            _id <= _currentTokenID,
            "ERC1155Tradable#create: ID is greater than currentTokenID"
        );
        creators[_id] = msg.sender;
        setAdd(_initialOwner, _id);
        _mint(_initialOwner, _id, _initialSupply, _data);
        tokenSupply[_id] = _initialSupply;
        caps[_id] = _cap;
        return _id;
    }

    /***********************************|
    |     Public Transfer Functions     |
    |__________________________________*/

    /**
     * @notice Transfers amount amount of an _id from the _from address to the _to address specified
     * @param _from    Source address
     * @param _to      Target address
     * @param _id      ID of the token type
     * @param _amount  Transfered amount
     * @param _data    Additional data with no specified format, sent in call to `_to`
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount,
        bytes memory _data
    ) public {
        require(
            (msg.sender == _from) || isApprovedForAll(_from, msg.sender),
            "ERC1155#safeTransferFrom: INVALID_OPERATOR"
        );
        require(
            _to != address(0),
            "ERC1155#safeTransferFrom: INVALID_RECIPIENT"
        );
        // require(_amount <= balances[_from][_id]) is not necessary since checked with safemath operations

        _safeTransferFrom(_from, _to, _id, _amount);
        _callonERC1155Received(_from, _to, _id, _amount, gasleft(), _data);

        if (balanceOf(_from, _id) == 0) {
            setRemove(_from, _id);
        }

        setAdd(_to, _id);
    }

    /**
     * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
     * @param _from     Source addresses
     * @param _to       Target addresses
     * @param _ids      IDs of each token type
     * @param _amounts  Transfer amounts per token type
     * @param _data     Additional data with no specified format, sent in call to `_to`
     */
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data
    ) public {
        // Requirements
        require(
            (msg.sender == _from) || isApprovedForAll(_from, msg.sender),
            "ERC1155#safeBatchTransferFrom: INVALID_OPERATOR"
        );
        require(
            _to != address(0),
            "ERC1155#safeBatchTransferFrom: INVALID_RECIPIENT"
        );

        _safeBatchTransferFrom(_from, _to, _ids, _amounts);
        _callonERC1155BatchReceived(
            _from,
            _to,
            _ids,
            _amounts,
            gasleft(),
            _data
        );

        for (uint256 i = 0; i < _ids.length; i++) {
            if (balanceOf(_from, _ids[i]) == 0) {
                setRemove(_from, _ids[i]);
            }

            setAdd(_to, _ids[i]);
        }
    }

    function mint(
        address _to,
        uint256 _id,
        uint256 _quantity,
        bytes memory _data
    ) public creatorOnly(_id) {
        if (caps[_id] != 0) {
            require(
                tokenSupply[_id].add(_quantity) <= caps[_id],
                "CRCN: OVER_THE_CAP"
            );
        }
        _mint(_to, _id, _quantity, _data);
        setAdd(_to, _id);
        tokenSupply[_id] = tokenSupply[_id].add(_quantity);
    }

    function batchMint(
        address _to,
        uint256[] memory _ids,
        uint256[] memory _quantities,
        bytes memory _data
    ) public {
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 _id = _ids[i];
            uint256 _quantity = _quantities[i];

            if (caps[_id] != 0) {
                require(
                    tokenSupply[_id].add(_quantity) <= caps[_id],
                    "CRCN: OVER_THE_CAP"
                );
            }
            require(creators[_id] == msg.sender, "CRCN: ONLY_CREATOR_ALLOWED");

            setAdd(_to, _id);
            tokenSupply[_id] = tokenSupply[_id].add(_quantity);
        }
        _batchMint(_to, _ids, _quantities, _data);
    }

    function setCreator(address _to, uint256[] memory _ids) public {
        require(_to != address(0), "CRCN: INVALID_ADDRESS.");
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            _setCreator(_to, id);
        }
    }

    function isApprovedForAll(address _owner, address _operator)
        public
        view
        returns (bool isOperator)
    {
        return ERC1155.isApprovedForAll(_owner, _operator);
    }

    function isTokenOwner(address _owner, uint256 _id)
        public
        view
        returns (bool)
    {
        if (balances[_owner][_id] > 0) {
            return true;
        }
        return false;
    }

    function ownerOf(uint256 _id) public view returns (address[] memory) {
        return owners[_id]._values;
    }

    function _getUri(uint256 _id) internal view returns (string memory) {
        require(_exists(_id), "ERC721Tradable#uri: NONEXISTENT_TOKEN");
        return Strings.strConcat(baseMetadataURI, Strings.uint2str(_id), _uri);
    }

    function _setCreator(address _to, uint256 _id) internal creatorOnly(_id) {
        creators[_id] = _to;
    }

    function _exists(uint256 _id) internal view returns (bool) {
        return creators[_id] != address(0);
    }

    function _getNextTokenID() private view returns (uint256) {
        uint256 _id = _currentTokenID.add(1);
        if (reservedId[_id]) {
            return _id.add(1);
        }
        return _id;
    }

    // ------------------ SET FUNCTIONS --------------------

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function setAdd(address owner, uint256 value) internal returns (bool) {
        if (!setContains(owner, value)) {
            holderTokens[owner]._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            holderTokens[owner]._indexes[value] = holderTokens[owner]
                ._values
                .length;

            owners[value]._values.push(owner);
            owners[value]._indexes[owner] = owners[value]._values.length;

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function setRemove(address owner, uint256 value) internal returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = holderTokens[owner]._indexes[value];
        uint256 ownerIndex = owners[value]._indexes[owner];

        if (valueIndex != 0) {
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteValueIndex = valueIndex - 1;
            uint256 lastIndex = holderTokens[owner]._values.length - 1;
            uint256 lastValue = holderTokens[owner]._values[lastIndex];
            holderTokens[owner]._values[toDeleteValueIndex] = lastValue;
            holderTokens[owner]._indexes[lastValue] = toDeleteValueIndex + 1; // All indexes are 1-based
            holderTokens[owner]._values.pop();
            delete holderTokens[owner]._indexes[value];

            uint256 toDeleteOwnerIndex = ownerIndex - 1;
            lastIndex = owners[value]._values.length - 1;
            address lastAddress = owners[value]._values[lastIndex];
            owners[value]._values[toDeleteOwnerIndex] = lastAddress;
            owners[value]._indexes[lastAddress] = toDeleteOwnerIndex + 1; // All indexes are 1-based
            owners[value]._values.pop();
            delete owners[value]._indexes[owner];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function setContains(address owner, uint256 value)
        public
        view
        returns (bool)
    {
        return holderTokens[owner]._indexes[value] != 0;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(address owner, uint256 index) public view returns (uint256) {
        Uint256Set memory set = holderTokens[owner];
        require(
            set._values.length > index,
            "EnumerableSet: index out of bounds"
        );
        return set._values[index];
    }
}
