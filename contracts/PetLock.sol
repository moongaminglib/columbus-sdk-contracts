pragma solidity =0.5.16;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import './SponsorWhitelistControl.sol';
import './libraries/Math.sol';
import './libraries/Tool.sol';
import './interfaces/ICustomNFT.sol';

/**
 *  NFT Lock
 */
contract PetLock is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));

    address public condragon;

    struct OrderInfo {
      string orderNo;
      uint256 tokenId;
      uint256 catId;
      uint256 nftLevel;
      uint256 isUsed;
    }

    // need clear order records when startup
    mapping(string => OrderInfo) public orders;
    // hero
    mapping(address => mapping(string => bool)) public heroHangup;

    address public petLockV1;

    struct LockInfo {
      address owner;
      uint256 tokenId;
      uint256 catId;
      uint256 nftLevel;
    }

    mapping(uint256 => LockInfo) public locks;

    // event
    event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint256 value);
    event TokenLock(address indexed from, address to, uint256 tokenId, string orderNo);
    event TokenUnLock(address indexed from, address to, uint256 tokenId, string orderNo);

    constructor(
          address _condragon,
          address _petLockV1
      ) public {
          condragon = _condragon;
          petLockV1 = _petLockV1;

          // register all users as sponsees
          address[] memory users = new address[](1);
          users[0] = address(0);
          SPONSOR.addPrivilege(users);
    }

    //
    function _lock(address _user, uint256 _tokenId, string memory _orderNo, string memory _heroId) internal {
        require(bytes(_orderNo).length > 0, "PetLock: orderNo is empty");
        OrderInfo storage _orderInfo = orders[_orderNo];
        require(_orderInfo.isUsed == 0, "PetLock: orderNo used");
        require(!heroHangup[_user][_heroId], "PetLock: the hero lock nft");
        LockInfo storage _lockInfo = locks[_tokenId];
        require(_lockInfo.tokenId == 0, "PetLock: tokenId lock");
        uint256 _catId = ICustomNFT(condragon).categoryOf(_tokenId);
        uint256 _nftLevel = ICustomNFT(condragon).levelOf(_tokenId);

        _orderInfo.orderNo = _orderNo;
        _orderInfo.tokenId = _tokenId;
        _orderInfo.catId = _catId;
        _orderInfo.nftLevel = _nftLevel;
        _orderInfo.isUsed = 1;

        _lockInfo.owner = _user;
        _lockInfo.tokenId = _tokenId;
        _lockInfo.catId = _catId;
        _lockInfo.nftLevel = _nftLevel;

        heroHangup[_user][_heroId] = true;

        emit TokenLock(_user, address(this), _tokenId, _orderNo);
    }

    function unlock(uint256 _tokenId, string calldata _orderNo, string calldata _heroId) external {
      require(bytes(_orderNo).length > 0, "PetLock: orderNo is empty");
      OrderInfo storage _orderInfo = orders[_orderNo];
      require(_orderInfo.isUsed == 0, "PetLock: orderNo used");
      LockInfo storage _lockInfo = locks[_tokenId];
      require(_lockInfo.tokenId > 0, "PetLock: tokenId no lock");
      require(_lockInfo.owner == msg.sender, "PetLock: no owner");

      uint256 _catId = ICustomNFT(condragon).categoryOf(_tokenId);
      uint256 _nftLevel = ICustomNFT(condragon).levelOf(_tokenId);

      _safeNFTTransfer(_lockInfo.owner, _tokenId);
      delete locks[_tokenId];

      _orderInfo.orderNo = _orderNo;
      _orderInfo.tokenId = _tokenId;
      _orderInfo.catId = _catId;
      _orderInfo.nftLevel = _nftLevel;
      _orderInfo.isUsed = 1;

      heroHangup[msg.sender][_heroId] = false;

      emit TokenUnLock(msg.sender, address(this), _tokenId, _orderNo);
    }

    function forceRetrieve(address _to, uint256 _tokenId) external onlyOwner{
        _safeNFTTransfer(_to, _tokenId);
        delete locks[_tokenId];
    }

    function cleanLock(uint256 _tokenId) external onlyOwner {
        delete locks[_tokenId];
    }

    function forceRetrieveAndHero(address _to, uint256 _tokenId, string calldata _heroId) external onlyOwner{
        _safeNFTTransfer(_to, _tokenId);
        delete locks[_tokenId];
        heroHangup[_to][_heroId] = false;
    }

    function cleanUserHero(address _user, string calldata _heroId) external onlyOwner {
        heroHangup[_user][_heroId] = false;
    }

    // restoreData
    function restoreData(address[] calldata _users, uint256[] calldata _tokenIds) external onlyOwner {
        require(_users.length == _tokenIds.length, "PetLock: length error");
        uint256 _range = _users.length;
        for(uint256 i = 0; i < _range; i ++){
          address _user = _users[i];
          uint256 _tokenId = _tokenIds[i];
          if(!ICustomNFT(condragon).isTokenOwner(address(this), _tokenId)){
             continue;
          }

          uint256 _catId = ICustomNFT(condragon).categoryOf(_tokenId);
          uint256 _nftLevel = ICustomNFT(condragon).levelOf(_tokenId);

          LockInfo memory _lockInfo = locks[_tokenId];
          _lockInfo.owner = _user;
          _lockInfo.tokenId = _tokenId;
          _lockInfo.catId = _catId;
          _lockInfo.nftLevel = _nftLevel;

          locks[_tokenId] = _lockInfo;
        }
    }

    function _safeNFTTransfer(address _to, uint256 _id) internal {
        ICustomNFT(condragon).safeTransferFrom(address(this), _to, _id, 1, '');
    }

    function onERC1155BatchReceived(
          address _operator,
          address _from,
          uint256[] calldata _ids,
          uint256[] calldata _amounts,
          bytes calldata _data) external returns(bytes4){

          return 0xbc197c81;
    }

    function onERC1155Received(
          address _operator,
          address _from,
          uint256 _id,
          uint256 _amount,
          bytes calldata _data) external returns(bytes4){

          if(_from == petLockV1){
            return 0xf23a6e61;
          }

          require(msg.sender == condragon, "Stake: only receive condragon");

          if(_data.length < 32) {
            revert("PayOrder: userdata is error");
          }

          (string memory _orderNo, string memory _heroId) = abi.decode(_data, (string, string));
          _lock(_from, _id, _orderNo, _heroId);

          return 0xf23a6e61;
    }

    function cleanOrders(string calldata _orderNo) external onlyOwner {
        delete orders[_orderNo];
    }
}
