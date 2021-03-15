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
import './interfaces/IConDragon.sol';

/**
 * Condragon NFT Battle
 */
contract PetBattle is Ownable {
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
    // pos
    mapping(address => mapping(string => bool)) public posHangup;

    struct LockInfo {
      address owner;
      uint256 tokenId;
      uint256 catId;
      uint256 nftLevel;
    }

    mapping(uint256 => LockInfo) public locks;
    mapping(address => uint256) public limits;
    uint256 public limitNum;

    // event
    event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint256 value);
    event TokenLock(address indexed from, address to, uint256 tokenId, string orderNo);
    event TokenUnLock(address indexed from, address to, uint256 tokenId, string orderNo);

    constructor(
          address _condragon
      ) public {
          condragon = _condragon;
          limitNum = 4;

          // register all users as sponsees
          address[] memory users = new address[](1);
          users[0] = address(0);
          SPONSOR.addPrivilege(users);
    }

    //
    function _lock(address _user, uint256 _tokenId, string memory _orderNo, string memory _posId) internal {
        require(bytes(_orderNo).length > 0, "PetLock: orderNo is empty");
        OrderInfo storage _orderInfo = orders[_orderNo];
        require(_orderInfo.isUsed == 0, "PetBattle: orderNo used");
        //require(!posHangup[_user][_posId], "PetBattle: the pos lock nft");
        require(limits[_user] < limitNum, "PetBattle: the limitnum over");
        LockInfo storage _lockInfo = locks[_tokenId];
        require(_lockInfo.tokenId == 0, "PetBattle: tokenId lock");
        uint256 _catId = IConDragon(condragon).categoryOf(_tokenId);
        uint256 _nftLevel = IConDragon(condragon).levelOf(_tokenId);

        _orderInfo.orderNo = _orderNo;
        _orderInfo.tokenId = _tokenId;
        _orderInfo.catId = _catId;
        _orderInfo.nftLevel = _nftLevel;
        _orderInfo.isUsed = 1;

        _lockInfo.owner = _user;
        _lockInfo.tokenId = _tokenId;
        _lockInfo.catId = _catId;
        _lockInfo.nftLevel = _nftLevel;

        limits[_user] = limits[_user].add(1);
        //posHangup[_user][_posId] = true;

        emit TokenLock(_user, address(this), _tokenId, _orderNo);
    }

    function unlock(uint256 _tokenId, string calldata _orderNo, string calldata _posId) external {
      require(bytes(_orderNo).length > 0, "PetBattle: orderNo is empty");
      OrderInfo storage _orderInfo = orders[_orderNo];
      require(_orderInfo.isUsed == 0, "PetBattle: orderNo used");
      LockInfo storage _lockInfo = locks[_tokenId];
      require(_lockInfo.tokenId > 0, "PetBattle: tokenId no lock");
      require(_lockInfo.owner == msg.sender, "PetLock: no owner");

      uint256 _catId = IConDragon(condragon).categoryOf(_tokenId);
      uint256 _nftLevel = IConDragon(condragon).levelOf(_tokenId);

      _safeNFTTransfer(_lockInfo.owner, _tokenId);
      delete locks[_tokenId];

      _orderInfo.orderNo = _orderNo;
      _orderInfo.tokenId = _tokenId;
      _orderInfo.catId = _catId;
      _orderInfo.nftLevel = _nftLevel;
      _orderInfo.isUsed = 1;

      if(limits[msg.sender] > 1)
        limits[msg.sender] = limits[msg.sender].sub(1);
      //posHangup[msg.sender][_posId] = false;

      emit TokenUnLock(msg.sender, address(this), _tokenId, _orderNo);
    }

    function forceRetrieve(address _to, uint256 _tokenId) external onlyOwner{
        _safeNFTTransfer(_to, _tokenId);
        delete locks[_tokenId];
        if(limits[_to] > 1)
          limits[_to] = limits[_to].sub(1);
    }

    function cleanLock(uint256 _tokenId) external onlyOwner {
        delete locks[_tokenId];
    }

    function setLimitNum(uint256 _limitNum) external onlyOwner {
       limitNum = _limitNum;
    }

    function forceRetrieveAndHero(address _to, uint256 _tokenId, string calldata _posId) external onlyOwner{
        _safeNFTTransfer(_to, _tokenId);
        delete locks[_tokenId];
        posHangup[_to][_posId] = false;
        if(limits[_to] > 1)
          limits[_to] = limits[_to].sub(1);
    }

    function cleanUserHero(address _user, string calldata _posId) external onlyOwner {
        posHangup[_user][_posId] = false;
    }

    function _safeNFTTransfer(address _to, uint256 _id) internal {
        IConDragon(condragon).safeTransferFrom(address(this), _to, _id, 1, '');
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

          require(msg.sender == condragon, "Stake: only receive condragon");

          if(_data.length < 32) {
            revert("PayOrder: userdata is error");
          }

          (string memory _orderNo, string memory _posId) = abi.decode(_data, (string, string));
          _lock(_from, _id, _orderNo, _posId);

          return 0xf23a6e61;
    }

    function cleanOrders(string calldata _orderNo) external onlyOwner {
        delete orders[_orderNo];
    }
}
