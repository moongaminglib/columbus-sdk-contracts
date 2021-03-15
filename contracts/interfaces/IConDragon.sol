pragma solidity 0.5.16;

contract IConDragon {
    function categoryOf(uint256 _tokenId) external view returns (uint256);

    function levelOf(uint256 _tokenId) external view returns (uint256);

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount,
        bytes calldata _data
    ) external;

    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external;

    function balanceOf(address _owner, uint256 _id)
        external
        view
        returns (uint256);

    function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids)
        external
        view
        returns (uint256[] memory);

    function setApprovalForAll(address _operator, bool _approved) external;

    function isApprovedForAll(address _owner, address _operator)
        external
        view
        returns (bool isOperator);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function batchBurnNFT(
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _amounts
    ) external;

    function burnNFT(
        address _from,
        uint256 _id,
        uint256 _amount
    ) external;

    function createNFT(
        address _initialOwner,
        uint256 _category,
        uint256 _level,
        uint256 _initialSupply,
        uint256 _cap,
        bytes calldata _data
    ) external returns (uint256 tokenId);

    function isTokenOwner(address _owner, uint256 _id)
        external
        view
        returns (bool);

    function ownerOf(uint256 _id) public view returns (address[] memory);
}
