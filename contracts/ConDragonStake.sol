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
 * NFT Stake Contract
 */
contract ConDragonStake is Ownable, IERC777Recipient {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));
    IERC1820Registry private _erc1820 = IERC1820Registry(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820);
    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
      0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    address public condragon;
    // weight (place rate * nft rate)
    address public cMoonToken;

    // weight config
    // catId => level
    mapping(uint256 => mapping(uint256 => uint256)) public nftRates;
    // price => placeRate
    mapping(uint256 => uint256) public lockRates;
    uint256 public maxPlace = 16; // place placeId from 2 placeId = 1 is free weight 1
    uint256 public endMaxBlock = 86400 * 2 * 7; // after 7 days lock no slash amount
    uint256 public slashRatio = 10;
    uint256 public devRatio = 20; // dev percent

    struct UserPlace {
      uint256 placeRate;
      uint256 price;
      uint256 lastLockBlock; //
      uint256 tokenId; // nft id
      uint256 nftCatId; // nft catId
      uint256 nftLevel; // nft level
      bool isLock;
      uint256 nftRate; // snapshot nft rate
    }

    // user => placeId => UserPlace
    mapping(address => mapping(uint256 => UserPlace)) public userPlaces;

    struct UserInfo {
      uint256 weight; // calc weight
      uint256 rewardDebt;
      uint256 balance;
    }

    // catId => amount
    mapping(uint256 => uint256) public totalStakes;

    mapping(address => UserInfo) public userInfo;
    // calc reward
    uint256 public totalWeight;

    uint256 public accTokenPerShare;
    uint256 public lastRewardBlock;
    uint256 public intervalBlock; // reward interval block num
    uint256 public totalPoolAmount;
    uint256 public poolBalance;
    address public devAddr;
    uint256 public apyRatio; // div 100000
    uint256 public apyDenominator = 100000;
    bool public outEnable; // game end open harvest
    bool public stakeEnable; // game stake enable
    uint256 public totalLockAmount;//

    // event
    event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint256 value);
    event TokenStake(address indexed from, address to, uint256 tokenId);
    event TokenUnStake(address indexed from, address to, uint256 tokenId);

    constructor(
          address _condragon,
          address _cMoonToken,
          address _devAddr
      ) public {
          condragon = _condragon;
          cMoonToken = _cMoonToken;
          devAddr = _devAddr;

          apyRatio = 5;
          intervalBlock = 120;

          outEnable = false;
          stakeEnable = true;

          _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

          // register all users as sponsees
          address[] memory users = new address[](1);
          users[0] = address(0);
          SPONSOR.addPrivilege(users);
    }

    // functions
    function setCondragon(address _condragon) external onlyOwner {
        condragon = _condragon;
    }

    function setEndMaxBlock(uint256 _endMaxBlock) external onlyOwner {
        endMaxBlock = _endMaxBlock;
    }

    function setSlashRatio(uint256 _slashRatio) external onlyOwner {
      slashRatio = _slashRatio;
    }

    function setMaxPlace(uint256 _maxPlace) external onlyOwner {
      require(_maxPlace > 0 && _maxPlace <= 20, "Stake: maxPlace limit invalid");
      maxPlace = _maxPlace;
    }

    function setDevRatio(uint256 _devRatio) external onlyOwner {
        devRatio = _devRatio;
    }

    function setApyRatio(uint256 _apyRatio) external onlyOwner {
        _poolLogic();
        apyRatio = _apyRatio;
    }

    function setApyDenominator(uint256 _apyDenominator) external onlyOwner {
        _poolLogic();
        apyDenominator = _apyDenominator;
    }

    function setNFTRates(uint256 catId, uint256[] calldata _levels, uint256[] calldata _rates) external onlyOwner {
        require(catId > 0, "Stake: catId error");
        require(_levels.length == _rates.length, "Stake: length diff");
        uint256 _range = _levels.length;

        for(uint256 i = 0; i < _range; i ++){
          nftRates[catId][_levels[i]] = _rates[i];
        }
    }

    function setNFTRate(uint256 _catId, uint256 _level, uint256 _rate) external onlyOwner {
      nftRates[_catId][_level] = _rate;
    }

    function setLockRates(uint256[] calldata _prices, uint256[] calldata _rates) external onlyOwner {
      require(_prices.length == _rates.length, "Stake: length diff");
      uint256 _range = _prices.length;

      for(uint256 i = 0; i < _range; i ++){
        lockRates[_prices[i]] = _rates[i];
      }
    }

    function setLockRate(uint256 _price, uint256 _rate) external onlyOwner {
      lockRates[_price] = _rate;
    }

    // lock place
    function _lockPlace(address _user, uint256 _placeId, uint256 _amount) internal {
      // check
      require(_placeId > 1 && _placeId <= maxPlace, "Stake: place range error");
      UserPlace storage _userPlace = userPlaces[_user][_placeId];
      require(!_userPlace.isLock, "Stake: the place is lock");
      require(lockRates[_amount] > 0, "Stake: lock PriceRate check failure");
      _userPlace.placeRate = lockRates[_amount];
      _userPlace.price = _amount;
      _userPlace.lastLockBlock = block.number;
      _userPlace.isLock = true;

      totalLockAmount = totalLockAmount.add(_amount);
    }

    // unlock
    // before unlock need unstake NFT
    function unlockPlace(uint256 _placeId) external {
      require(_placeId > 1 && _placeId <= maxPlace, "Stake: place range error");
      address _user = msg.sender;
      UserPlace storage _userPlace = userPlaces[_user][_placeId];
      require(_userPlace.isLock, "Stake: the place is lock");
      require(_userPlace.tokenId == 0, "Stake: exists tokenId");
      require(_userPlace.price > 0, "Stake: price not zero");
      if(totalLockAmount >= _userPlace.price){
        totalLockAmount = totalLockAmount.sub(_userPlace.price);
      }

      if(block.number < _userPlace.lastLockBlock.add(endMaxBlock)){
        // slash
        uint256 _slashAmount = _userPlace.price.mul(slashRatio).div(100);
        // 20% to DEVADDR
        uint256 _devAmount = _slashAmount.mul(devRatio).div(100);
        _safeTokenTransfer(_user, _userPlace.price.sub(_slashAmount));
        _safeTokenTransfer(devAddr, _devAmount);

        _poolLogic();
        totalPoolAmount = totalPoolAmount.add(_slashAmount.sub(_devAmount));
        poolBalance = poolBalance.add(_slashAmount.sub(_devAmount));
      }else{
        _safeTokenTransfer(_user, _userPlace.price);
      }

      _userPlace.isLock = false;
      _userPlace.price = 0;
      _userPlace.lastLockBlock = 0;
      _userPlace.placeRate = 0;
    }

    // into pool
    function _inPool(uint256 _amount) internal {
        _poolLogic();
        totalPoolAmount = totalPoolAmount.add(_amount);
        poolBalance = poolBalance.add(_amount);
    }

    // Stake NFT
    function _stake(address _user, uint256 _placeId, uint256 _tokenId) internal {
      //check
      require(totalPoolAmount > 0, "Stake: no start");
      require(stakeEnable, "Stake: stake no start");
      require(_placeId > 0 && _placeId <= maxPlace, "Stake: place range error");
      UserPlace storage _userPlace = userPlaces[_user][_placeId];
      if(_placeId == 1){
        _userPlace.placeRate = 1;
        _userPlace.isLock = true;
      }
      require(_userPlace.isLock, "Stake: place is not lock");
      require(_userPlace.tokenId == 0, "Stake: exists tokenId");

      uint256 _catId = IConDragon(condragon).categoryOf(_tokenId);
      uint256 _level = IConDragon(condragon).levelOf(_tokenId);
      require(_catId > 0, "Stake: catId invalid");
      require(_level > 0, "Stake: level invalid");
      uint256 _nftRate = nftRates[_catId][_level];
      require(_nftRate > 0, "Stake: no config nftRate");
      _userPlace.tokenId = _tokenId;
      _userPlace.nftCatId = _catId;
      _userPlace.nftLevel = _level;
      _userPlace.nftRate = _nftRate;
      _poolLogic();
      emit TokenStake(_user, address(this), _tokenId);
      // record profit
      {
         UserInfo storage _userInfo = userInfo[_user];
         uint256 pending = _userInfo.weight.mul(accTokenPerShare).div(1e12).sub(_userInfo.rewardDebt);
         _userInfo.balance = _userInfo.balance.add(pending);

         uint256 _weight = _userPlace.placeRate.mul(_nftRate);
         _userInfo.weight = _userInfo.weight.add(_weight);
         totalWeight = totalWeight.add(_weight);
         _userInfo.rewardDebt = _userInfo.weight.mul(accTokenPerShare).div(1e12);
      }

      //
      totalStakes[_catId] = totalStakes[_catId].add(1);
    }

    // unstake NFT
    function unstake(uint256 _placeId) external {
        require(_placeId > 0 && _placeId <= maxPlace, "Stake: place range error");
        address _user = msg.sender;
        UserPlace storage _userPlace = userPlaces[_user][_placeId];
        require(_userPlace.tokenId > 0, "Stake: exists tokenId");

        uint256 _tokenId = _userPlace.tokenId;
        uint256 _catId = _userPlace.nftCatId;
        uint256 _nftRate = _userPlace.nftRate;

        _poolLogic();

        emit TokenUnStake(address(this), _user, _tokenId);
        {
            UserInfo storage _userInfo = userInfo[_user];
            uint256 pending = _userInfo.weight.mul(accTokenPerShare).div(1e12).sub(_userInfo.rewardDebt);
            _userInfo.balance = _userInfo.balance.add(pending);

            uint256 _weight = _userPlace.placeRate.mul(_nftRate);
            _userInfo.weight = _userInfo.weight.sub(_weight);
            totalWeight = totalWeight.sub(_weight);
            _userInfo.rewardDebt = _userInfo.weight.mul(accTokenPerShare).div(1e12);
        }

        //
        if(totalStakes[_catId] > 0){
          totalStakes[_catId] = totalStakes[_catId].sub(1);
        }

        _userPlace.tokenId = 0;
        _userPlace.nftCatId = 0;
        _userPlace.nftLevel = 0;
        _userPlace.nftRate = 0;

        _safeNFTTransfer(_user, _tokenId);
    }

    //
    function harvest() external {
      UserInfo storage user = userInfo[msg.sender];
      require(outEnable, "Stake: outEnable is closed");
      _poolLogic();
      uint256 pending = user.weight.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
      pending = user.balance.add(pending);
      user.rewardDebt = user.weight.mul(accTokenPerShare).div(1e12);
      user.balance = 0;
      if(pending > 0){
        _safeTokenTransfer(msg.sender, pending);
      }
    }

    function getAllPlace(address _user) external view returns(UserPlace[20] memory){
      UserPlace[20] memory _userPlaces;
      for(uint256 i = 1;i <= maxPlace; i ++){
        _userPlaces[i - 1] = userPlaces[_user][i];
      }

      return _userPlaces;
    }

    function getTotalStakes(uint256 _maxCatId) external view returns(uint256[20] memory, uint256[20] memory) {
      uint256[20] memory _catIds;
      uint256[20] memory _totalNums;
      for(uint256 i = 1; i <= _maxCatId; i ++){
         _catIds[i - 1] = i;
         _totalNums[i - 1] = totalStakes[i];
      }

      return (_catIds, _totalNums);
    }

    // MultiSigWalletWithTimeLock future
    // Withdraw EMERGENCY ONLY.
    function emergencyWithdraw(address tokenAddress, address to, uint256 _amount) external onlyOwner {
        IERC777(tokenAddress).send(to, _amount, "");
    }

    function pendingToken(address _user) external view returns(uint256) {
      UserInfo storage user = userInfo[_user];
      uint256 _accTokenPerShare = accTokenPerShare;
      if (block.number > lastRewardBlock && totalWeight > 0) {
          uint256 shareReward = poolBalance
              .mul(block.number.sub(lastRewardBlock).div(intervalBlock))
              .mul(apyRatio)
              .div(apyDenominator);

          _accTokenPerShare = _accTokenPerShare.add(shareReward.mul(1e12).div(totalWeight));
      }

      uint256 pending = user.weight.mul(_accTokenPerShare).div(1e12).sub(user.rewardDebt);
      return user.balance.add(pending);
    }

    function forceRetrieve(address _to, uint256 _tokenId) external onlyOwner{
        _safeNFTTransfer(_to, _tokenId);
    }

    function _poolLogic() internal {
      if(poolBalance == 0){
        lastRewardBlock = block.number;
        return;
      }
      if(intervalBlock == 0){
        return;
      }
      if(intervalBlock > block.number){
        return;
      }
      if(block.number.sub(intervalBlock) <= lastRewardBlock){
        return;
      }
      if(totalWeight == 0){
        lastRewardBlock = block.number;
        return;
      }

      uint256 _times = block.number.sub(lastRewardBlock).div(intervalBlock);
      uint256 shareReward = poolBalance
            .mul(_times)
            .mul(apyRatio)
            .div(apyDenominator);
      if(shareReward > poolBalance){
          shareReward = poolBalance;
      }

      poolBalance = poolBalance.sub(shareReward);
      accTokenPerShare = accTokenPerShare.add(shareReward.mul(1e12).div(totalWeight));
      lastRewardBlock = lastRewardBlock.add(intervalBlock.mul(_times));
    }

    function _safeNFTTransfer(address _to, uint256 _id) internal {
        IConDragon(condragon).safeTransferFrom(address(this), _to, _id, 1, '');
    }

    function _safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = IERC20(cMoonToken).balanceOf(address(this));
        require(_amount <= tokenBal, "Stake: cMoon insufficient");
        IERC20(cMoonToken).transfer(_to, _amount);
    }

    function onERC1155BatchReceived(
          address _operator,
          address _from,
          uint256[] calldata _ids,
          uint256[] calldata _amounts,
          bytes calldata _data) external returns(bytes4){

          if(_ids.length > 0){
            revert("Stake: no support batch transfer");
          }

          return 0xbc197c81;
    }

    function onERC1155Received(
          address _operator,
          address _from,
          uint256 _id,
          uint256 _amount,
          bytes calldata _data) external returns(bytes4){

          require(msg.sender == condragon, "Stake: only receive condragon");

          if(_data.length > 0 && _data[0] == 0x01) {
            uint256 _placeId = Tool.parseDataPlace(_data, 32);
            _stake(_from, _placeId, _id);
          }else{
            revert("Stake: no support operator");
          }

          return 0xf23a6e61;
    }

    // erc777 receiveToken
    function tokensReceived(address operator, address from, address to, uint amount,
          bytes calldata userData,
          bytes calldata operatorData) external {

          require(msg.sender == cMoonToken, "Stake: only receive cMoon");

          if(userData.length > 0 && userData[0] == 0x02) {
            // input pool
            _inPool(amount);
          }else if(userData.length > 0 && userData[0] == 0x01){
            // place
            uint256 _placeId = Tool.parseDataPlace(userData, 32);
            _lockPlace(from, _placeId, amount);
          }

          emit TokenTransfer(msg.sender, from, to, amount);
    }

    function setDevAddr(address _devAddr) external onlyOwner {
        devAddr = _devAddr;
    }

    function setOutEnable(bool _outEnable) external onlyOwner {
       outEnable = _outEnable;
    }

    function setStakeEnable(bool _stakeEnable) external onlyOwner {
       stakeEnable = _stakeEnable;
    }
}
