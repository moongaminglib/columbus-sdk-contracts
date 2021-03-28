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
import './interfaces/IWCFX.sol';

/**
 *  functions:
 * 1、payorder by order_no; 2、c2c trade
 */
contract PayOrder is Ownable, IERC777Recipient {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));
    IERC1820Registry private _erc1820 = IERC1820Registry(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820);
    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
      0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    address public devAddr;
    uint256 public devRatio; // c2c 10% to dev

    address public poolAddr;
    uint256 public poolRatio;
    // basic
    address public cMoonToken;
    address public fcToken;
    address public wcfx;
    address public swapRoute;
    mapping(address => address[]) public swapPaths;

    enum PayType {
        WCFX,
        FC,
        CMOON
    }

    struct OrderInfo {
      string orderNo;
      address buyer;
      address seller;
      PayType payType;
      uint256 amount;
    }

    // need clear order records when startup
    mapping(string => OrderInfo) public orders;

    // event
    event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint256 value);
    event PayOrderEvent(address indexed tokenAddress, address indexed from, string orderNo, uint256 value, address seller);

    constructor(
          address _cMoonToken,
          address _fcToken,
          address _wcfx,
          address _devAddr,
          address _poolAddr,
          address _swapRoute
      ) public {
          cMoonToken = _cMoonToken;
          fcToken = _fcToken;
          wcfx = _wcfx;
          devAddr = _devAddr;
          poolAddr = _poolAddr;
          swapRoute = _swapRoute;

          devRatio = 5;
          poolRatio = 50;

          _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

          // register all users as sponsees
          address[] memory users = new address[](1);
          users[0] = address(0);
          SPONSOR.addPrivilege(users);
    }

    function setMoonToken(address _devAddr) external onlyOwner {
      require(_devAddr != address(0), "PayOrder: ZERO_ADDRESS");
      devAddr = _devAddr;
    }

    function setFcToken(address _fcToken) external onlyOwner {
        require(_fcToken != address(0), "PayOrder: ZERO_ADDRESS");
        fcToken = _fcToken;
    }

    function setWcfx(address _wcfx) external onlyOwner {
       require(_wcfx != address(0), "PayOrder: ZERO_ADDRESS");
       wcfx = _wcfx;
    }

    function setDevAddr(address _devAddr) external onlyOwner {
       require(_devAddr != address(0), "PayOrder: ZERO_ADDRESS");
       devAddr = _devAddr;
    }

    function setPoolRatio(uint256 _poolRatio) external onlyOwner {
        poolRatio = _poolRatio;
    }

    function setPoolAddr(address _poolAddr) external onlyOwner {
      require(_poolAddr != address(0), "PayOrder: ZERO_ADDRESS");
      poolAddr = _poolAddr;
    }

    function setSwapRoute(address _swapRoute) external onlyOwner {
        require(swapRoute != _swapRoute, "PayOrder: repeat operation!!!");
        swapRoute = _swapRoute;
    }

    function setSwapTokenPath(
        address _token,
        address[] calldata _paths
    ) external onlyOwner {
        swapPaths[_token] = _paths;
    }

    function getTokenPathLen(address _token) public view returns(uint256) {
      return swapPaths[_token].length;
    }

    // b2c sale
    function payCFX(string calldata orderNo) external payable {
        PayType payType = PayType.WCFX;
        _pay(msg.sender, wcfx, msg.value, orderNo, address(0));
    }

    // c2c sale
    function buyCFX(string calldata orderNo, address _seller) external payable {
        require(_seller != address(0), "PayOrder: seller is empty");
        PayType payType = PayType.WCFX;
        _pay(msg.sender, wcfx, msg.value, orderNo, _seller);
    }

    function _pay(address _user, address _token, uint256 _amount,
                  string memory _orderNo,
                  address _seller) internal {
        OrderInfo storage _orderInfo = orders[_orderNo];
        require(_orderInfo.buyer == address(0), "PayOrder: payed");
        require(bytes(_orderNo).length > 0, "PayOrder: orderNo is nil");
        require(_user != _seller, "PayOrder: buyer diff seller");
        _orderInfo.orderNo = _orderNo;
        _orderInfo.buyer = _user;
        _orderInfo.seller = _seller;
        PayType _payType;
        if(_token == wcfx){
          _payType = PayType.WCFX;
        }else if(_token == fcToken){
          _payType = PayType.FC;
        }else if(_token == cMoonToken){
          _payType = PayType.CMOON;
        }else{
          revert("PayOrder: no support Token");
        }

        _orderInfo.amount = _amount;
        _orderInfo.payType = _payType;
        if(_seller != address(0)){
          //
          uint256 _incomeAmount = _amount.mul(devRatio).div(100);
          uint256 _sellerAmount = _amount.sub(_incomeAmount);
          uint256 _poolAmount = _incomeAmount.mul(poolRatio).div(100);
          uint256 _devAmount = _incomeAmount.sub(_poolAmount);
          if(_payType == PayType.WCFX){
              _transferCFX(devAddr, _devAmount);
              _transferCFX(_seller, _sellerAmount);
          }else{
            _safeTokenTransfer(_token, devAddr, _devAmount);
            _safeTokenTransfer(_token, _seller, _sellerAmount);
          }
          // to poolAddr
          _transfercMoonToPool(_token, _poolAmount);
        }else{
          uint256 _poolAmount = _amount.mul(poolRatio).div(100);
          uint256 _devAmount = _amount.sub(_poolAmount);
          if(_payType == PayType.WCFX){
            _transferCFX(devAddr, _devAmount);
          }else{
            _safeTokenTransfer(_token, devAddr, _devAmount);
          }

          // to PoolAddr
          _transfercMoonToPool(_token, _poolAmount);
        }

        emit PayOrderEvent(_token, _user, _orderNo, _amount, _seller);
    }

    function _transfercMoonToPool(
      address _token,
      uint256 _poolAmount
    ) internal {
      if(_poolAmount <= 0){
          return;
      }
      if(_token == cMoonToken){
         _safeTokenTransfer(_token, poolAddr, _poolAmount);
         return;
      }

      address[] memory _paths = swapPaths[_token];
      require(_paths.length > 0, "PayOrder: path is empty!");
      if(_token == wcfx){
        ISwapRoute(swapRoute).swapExactCFXForTokens.value(_poolAmount)(
              0,
              _paths,
              poolAddr,
              now + 60
        );
      }else{
        IERC20(_token).approve(swapRoute, uint256(-1));
        ISwapRoute(swapRoute).swapExactTokensForTokens(
              _poolAmount,
              0,
              _paths,
              poolAddr,
              now + 60
        );
      }
    }

    // erc777 receiveToken
    function tokensReceived(address operator, address from, address to, uint amount,
          bytes calldata userData,
          bytes calldata operatorData) external {
          if(msg.sender == wcfx){
            return;
          }

          if(userData.length < 64) {
            revert("PayOrder: userdata is error");
          }
          if(msg.sender != fcToken && msg.sender != cMoonToken){
            revert("PayOrder: token no match");
          }

          (string memory _orderNo, address _seller) = abi.decode(userData, (string, address));

          _pay(from, msg.sender, amount, _orderNo, _seller);
          emit TokenTransfer(msg.sender, from, to, amount);
    }

    function() external payable {}

    function _transferCFX(address _user, uint256 _amount) internal {
      address payable toAddress = address(uint160(_user));
      toAddress.transfer(_amount);
    }

    function _safeTokenTransfer(address _token, address _to, uint256 _amount) internal {
        IERC20(_token).transfer(_to, _amount);
    }

    function setDevRatio(uint256 _devRatio) external onlyOwner {
      devRatio = _devRatio;
    }

    function cleanOrders(string calldata _orderNo) external onlyOwner {
        delete orders[_orderNo];
    }
}

interface ISwapRoute {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactCFXForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
}
