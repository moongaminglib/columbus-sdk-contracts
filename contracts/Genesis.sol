pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";

import "./crcn/CRCN.sol";
import "./SponsorWhitelistControl.sol";

/**
 * @title MoonswapGenesisHero
 * Genesis - a contract for my semi-fungible tokens.
 */
contract Genesis is CRCN, IERC777Sender, ReentrancyGuard {
    event Opened(address indexed account, uint256 id, uint256 categoryId);
    event Forged(address indexed account, uint256[] ids, uint256 bounty);

    IERC1820Registry constant private ERC1820_REGISTRY = IERC1820Registry(address(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820));

    address public devAddr;

    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));

    constructor( address _devAddr, string memory _baseMetadataURI)
        CRCN("MoonswapHero", "GENESIS")
    public {
        devAddr = _devAddr;
        _setBaseMetadataURI(_baseMetadataURI);

        ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777TokensSender"), address(this));

        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    // IERC777Sender
    function tokensToSend(
        address,
        address from,
        address,
        uint256,
        bytes memory,
        bytes memory
    ) public
    {
        require(from == address(this), "Genesis: deposit not authorized");
    }

    function setDevAddr(address _devAddr) public onlyOwner {
        devAddr = _devAddr;
    }

    function uri(uint256 _id) public view returns (string memory) {
        return _getUri(_id);
    }

    function batchCreateNFT(
        address[] calldata _initialOwners,
        string[] calldata _uris,
        bytes calldata _data
    ) external onlyOwner nonReentrant returns (uint256[] memory tokenIds) {
        require(_initialOwners.length == _uris.length, "Genesis: uri length mismatch");
        tokenIds = new uint256[](_initialOwners.length);
        for (uint i = 0; i < _initialOwners.length; i++) {
            tokenIds[i] = createNFT(_initialOwners[i], _uris[i], _data);
        }
    }

    function createNFT(
        address _initialOwner,
        string memory _uri,
        bytes memory _data
    ) public onlyOwner returns (uint256 tokenId) {
        tokenId = create(_initialOwner, 1, 1, _uri, _data);
    }
}
