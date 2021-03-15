pragma solidity 0.5.16;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "./SponsorWhitelistControl.sol";
import "./ERC1155/interfaces/IERC1155TokenReceiver.sol";
import "./ERC1155/interfaces/IERC1155.sol";
import "./interfaces/ISwapRoute.sol";

/**
 * Auction NFT Contract
 */
contract AuctionNFT is IERC777Recipient, Ownable, IERC1155TokenReceiver {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	bytes4 internal constant ERC1155_RECEIVED_VALUE = 0xf23a6e61;
	bytes4 internal constant ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

	SponsorWhitelistControl public constant SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));
	IERC1820Registry private _erc1820 = IERC1820Registry(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820);
	// keccak256("ERC777TokensRecipient")
	bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH = 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;
	address public poolAddr;
	uint256 public buyerNumerator;
	uint256 public poolNumerator;
	uint256 public priceNumerator;
	uint256 public userPoolNumerator;
	uint256 public userDevNumerator;
	uint256 public userBuyerNumerator;
	address public devAddr;
	uint256 public maxATCount;
	uint256 public coolDownTime;
	uint256 public cumulativeTime;
	mapping(address => mapping(uint256 => uint256)) public userBid;
	mapping(address => mapping(uint256 => uint256)) public nftAuctionId;
	mapping(uint256 => uint256) public ATCount;
	address public swapRoute;
	address public cMoon;
	mapping(uint256 => AuctionInfo) public auctionList;
	uint256 public currenAucId;

	struct AuctionInfo {
		address nft;
		uint256 tokenId;
		address buyer;
		uint256 buyPrice;
		uint256 onePrice;
		uint256 endBlock;
		uint256 newPrice;
		bool isEnd;
		uint256 poolAmount;
		address seller;
		uint256 sellerAmount;
		uint256 bidCount;
	}

	event UserBid(address user, uint256 aucId, uint256 amount, address profitUser, uint256 userProfit, uint256 blockNumber);
	event AddAuction(address nft, uint256 tokenId, uint256 aucId);
	event UpdateAuction(uint256 aucId, uint8 identify);

	constructor(
		address _cMoon,
		address _swapRoute,
		address _devAddr,
		address _poolAddr,
		uint256 _currenAucId
	) public {
		cMoon = _cMoon;
		swapRoute = _swapRoute;
		devAddr = _devAddr;
		poolAddr = _poolAddr;
		currenAucId = _currenAucId;
		_erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
		buyerNumerator = 20;
		poolNumerator = 50;
		priceNumerator = 110;
		coolDownTime = 60 minutes;
		cumulativeTime = 10 minutes;
		userPoolNumerator = 150;
		userDevNumerator = 150;
		userBuyerNumerator = 2000;
		// register all users as sponsees
		address[] memory users = new address[](1);
		users[0] = address(0);
		SPONSOR.addPrivilege(users);
	}

	function setUserAuctionNumber(
		uint256 _userPoolNumerator,
		uint256 _userDevNumerator,
		uint256 _userBuyerNumerator
	) external onlyOwner {
		userPoolNumerator = _userPoolNumerator;
		userDevNumerator = _userDevNumerator;
		userBuyerNumerator = _userBuyerNumerator;
	}

	function setOfficalNumerator(uint256 _buyerNumerator, uint256 _poolNumerator) external onlyOwner {
		require(buyerNumerator != _buyerNumerator || poolNumerator != _poolNumerator, "repeat operation!!!");
		buyerNumerator = _buyerNumerator;
		poolNumerator = _poolNumerator;
	}

	function setSwapRoute(address _swapRoute) external onlyOwner {
		require(swapRoute != _swapRoute, "repeat operation!!!");
		swapRoute = _swapRoute;
	}

	function setCoolDownTime(uint256 _coolDownTime) external onlyOwner {
		require(coolDownTime != _coolDownTime, "repeat operation!!!");
		coolDownTime = _coolDownTime;
	}

	function setCumulativeTime(uint256 _cumulativeTime) external onlyOwner {
		require(cumulativeTime != _cumulativeTime, "repeat operation!!!");
		cumulativeTime = _cumulativeTime;
	}

	function setPriceNumerator(uint256 _priceNumerator) external onlyOwner {
		require(priceNumerator != _priceNumerator, "repeat operation!!!");
		require(_priceNumerator > 100, "Not less than 100%");
		priceNumerator = _priceNumerator;
	}

	function setMaxATCount(uint256 _maxATCount) external onlyOwner {
		require(maxATCount != _maxATCount, "repeat operation!!!");
		maxATCount = _maxATCount;
	}

	function setDevAddr(address _devAddr) external onlyOwner {
		require(devAddr != _devAddr, "same address!!!");
		devAddr = _devAddr;
	}

	function setEndBlock(uint256 aucId, uint256 _endBock) external onlyOwner {
		require(auctionList[aucId].endBlock != _endBock, "repeat operation!!!");
		auctionList[aucId].endBlock = _endBock;
	}

	function setPoolAddr(address _poolAddr) external onlyOwner {
		require(poolAddr != _poolAddr, "same address!!!");
		poolAddr = _poolAddr;
	}

	function addBlock(uint256 time) internal view returns (uint256) {
		return time.mul(2);
	}

	function remainSec(uint256 aucId) public view returns (uint256) {
		if (block.number >= auctionList[aucId].endBlock) {
			return 0;
		}
		return auctionList[aucId].endBlock.sub(block.number).div(2);
	}

	// erc777 receiveToken
	function tokensReceived(
		address operator,
		address from,
		address to,
		uint256 amount,
		bytes calldata userData,
		bytes calldata operatorData
	) external {
		if (userData.length == 0) {
			return;
		}
		if (cMoon == msg.sender) {
			uint256 aucId = abi.decode(userData, (uint256));
			_userBid(aucId, from, amount);
			return;
		}
		(uint256 aucId, address[] memory _paths) = abi.decode(userData, (uint256, address[]));
		require(_paths[_paths.length - 1] == cMoon, "auction:paths error!!!");
		require(_paths[0] == msg.sender, "auction:paths error!!!");
		IERC20(msg.sender).approve(swapRoute, amount);
		uint256[] memory amounts = ISwapRoute(swapRoute).swapTokensForExactTokens(auctionList[aucId].newPrice, amount, _paths, address(this), now + 1800);
		if (amount - amounts[0] > 0) {
			IERC20(msg.sender).safeTransfer(from, amount.sub(amounts[0]));
		}
		_userBid(aucId, from, amounts[amounts.length - 1]);
	}

	function() external payable {
		require(msg.sender == swapRoute, "only swapRoute");
	}

	function cfxBid(uint256 aucId, address[] calldata _paths) external payable {
		require(_paths[_paths.length - 1] == cMoon, "auction:paths error!!!");
		uint256[] memory amounts = ISwapRoute(swapRoute).swapCFXForExactTokens.value(msg.value)(auctionList[aucId].newPrice, _paths, address(this), now + 1800);
		if (msg.value - amounts[0] > 0) {
			safeTransferCFX(msg.sender, msg.value.sub(amounts[0]));
		}
		_userBid(aucId, msg.sender, amounts[amounts.length - 1]);
	}

	function safeTransferCFX(address to, uint256 value) internal {
		(bool success, ) = to.call.value(value)(new bytes(0));
		require(success, "TransferHelper: ETH_TRANSFER_FAILED");
	}

	function _userBid(
		uint256 aucId,
		address from,
		uint256 amount
	) internal {
		AuctionInfo storage _auctionInfo = auctionList[aucId];
		require(_auctionInfo.endBlock > block.number, "auction is end");
		require(!_auctionInfo.isEnd, "auction is end");
		require(_auctionInfo.buyer != from, "Can't re-bid yourself");
		assert(amount > 0);
		require(amount == _auctionInfo.newPrice || amount == _auctionInfo.onePrice, "Has been taken away first, please re-bid");
		if (_auctionInfo.seller == address(0)) {
			emit UserBid(from, aucId, amount, _auctionInfo.buyer, _officalProfit(_auctionInfo, amount), block.number);
		} else {
			emit UserBid(from, aucId, amount, _auctionInfo.buyer, _userProfit(_auctionInfo, amount), block.number);
		}
		uint256 minutes60Block = block.number.add(addBlock(coolDownTime));
		if (_auctionInfo.endBlock < minutes60Block && (maxATCount == 0 || maxATCount > ATCount[aucId])) {
			_auctionInfo.endBlock = _auctionInfo.endBlock.add(addBlock(cumulativeTime));
			if (_auctionInfo.endBlock > minutes60Block) {
				_auctionInfo.endBlock = minutes60Block;
			}
			ATCount[aucId]++;
		}
		_auctionInfo.buyer = from;
		_auctionInfo.buyPrice = amount;
		_auctionInfo.bidCount++;
		if (_auctionInfo.onePrice == amount) {
			_completeAuction(_auctionInfo, aucId);
		} else {
			_auctionInfo.newPrice = amount.mul(priceNumerator).div(100);
			if (_auctionInfo.newPrice > _auctionInfo.onePrice) {
				_auctionInfo.newPrice = _auctionInfo.onePrice;
			}
		}
		userBid[from][aucId] = amount;
	}

	function _userProfit(AuctionInfo storage _auctionInfo, uint256 amount) internal returns (uint256) {
		uint256 buyerProfit;
		if (_auctionInfo.buyer != address(0)) {
			buyerProfit = amount.sub(_auctionInfo.buyPrice).mul(userBuyerNumerator).div(10000);
			uint256 buyerAmount = _auctionInfo.buyPrice.add(buyerProfit);
			IERC20(cMoon).safeTransfer(_auctionInfo.buyer, buyerAmount);
			_auctionInfo.sellerAmount = _auctionInfo.sellerAmount.add(amount.sub(buyerAmount));
		} else {
			_auctionInfo.sellerAmount = amount;
		}
		_auctionInfo.poolAmount = _auctionInfo.sellerAmount.mul(userPoolNumerator).div(10000);
		return buyerProfit;
	}

	function _officalProfit(AuctionInfo storage _auctionInfo, uint256 amount) internal returns (uint256) {
		uint256 devAmount;
		uint256 poolAmount;
		uint256 buyerProfit;
		if (_auctionInfo.buyer != address(0)) {
			buyerProfit = amount.sub(_auctionInfo.buyPrice).mul(buyerNumerator).div(100);
			uint256 buyerAmount = _auctionInfo.buyPrice.add(buyerProfit);
			IERC20(cMoon).safeTransfer(_auctionInfo.buyer, buyerAmount);
			poolAmount = amount.sub(buyerAmount).mul(poolNumerator).div(100);
			devAmount = amount.sub(buyerAmount).sub(poolAmount);
		} else {
			poolAmount = amount.mul(poolNumerator).div(100);
			devAmount = amount.sub(poolAmount);
		}
		IERC20(cMoon).safeTransfer(devAddr, devAmount);
		IERC20(cMoon).safeTransfer(poolAddr, poolAmount);
		_auctionInfo.poolAmount = _auctionInfo.poolAmount.add(poolAmount);
		return buyerProfit;
	}

	function addAuction(
		address nft,
		uint256 tokenId,
		uint256 newPrice,
		uint256 onePrice,
		address seller,
		uint256 totalCountdown
	) internal {
		require(nftAuctionId[nft][tokenId] == 0, "nft is on sale");
		currenAucId++;
		AuctionInfo storage _auctionInfo = auctionList[currenAucId];
		_auctionInfo.nft = nft;
		_auctionInfo.tokenId = tokenId;
		require(newPrice > 0, "auction:start price must be greater than 0");
		require(onePrice == 0 || onePrice > newPrice, "auction:onePrice must be greater than newPrice");
		_auctionInfo.newPrice = newPrice;
		_auctionInfo.onePrice = onePrice;
		_auctionInfo.seller = seller;
		_auctionInfo.endBlock = block.number.add(addBlock(totalCountdown));
		nftAuctionId[nft][tokenId] = currenAucId;
		emit AddAuction(nft, tokenId, currenAucId);
	}

	function cancelAuction(address _nft, uint256 _tokenId) external {
		uint256 aucId = nftAuctionId[_nft][_tokenId];
		require(aucId > 0, "not in auction");
		AuctionInfo storage _auctionInfo = auctionList[aucId];
		require(_auctionInfo.buyer == address(0), "has auction");
		require(msg.sender == _auctionInfo.seller, "user not seller");
		require(block.number < _auctionInfo.endBlock, "auction is end");
		require(!_auctionInfo.isEnd, "auction is end");
		_auctionInfo.isEnd = true;
		IERC1155(_nft).safeTransferFrom(address(this), _auctionInfo.seller, _tokenId, 1, "");
		delete nftAuctionId[_nft][_tokenId];
		emit UpdateAuction(aucId, 1);
	}

	function completeAuction(uint256 aucId) external {
		AuctionInfo storage _auctionInfo = auctionList[aucId];
		require(!_auctionInfo.isEnd, "auction is end");
		require(block.number > _auctionInfo.endBlock, "auction is not end");
		_completeAuction(_auctionInfo, aucId);
	}

	function _completeAuction(AuctionInfo storage _auctionInfo, uint256 aucId) internal {
		//购买成功
		if (_auctionInfo.buyer != address(0)) {
			//社区拍卖
			if (_auctionInfo.seller != address(0)) {
				uint256 devAmount = _auctionInfo.sellerAmount.mul(userDevNumerator).div(10000);
				uint256 sellerAmount = _auctionInfo.sellerAmount.sub(devAmount).sub(_auctionInfo.poolAmount);
				IERC20(cMoon).safeTransfer(devAddr, devAmount);
				IERC20(cMoon).safeTransfer(poolAddr, _auctionInfo.poolAmount);
				IERC20(cMoon).safeTransfer(_auctionInfo.seller, sellerAmount);
			}
			IERC1155(_auctionInfo.nft).safeTransferFrom(address(this), _auctionInfo.buyer, _auctionInfo.tokenId, 1, "");
		} else {
			if (_auctionInfo.seller != address(0)) {
				IERC1155(_auctionInfo.nft).safeTransferFrom(address(this), _auctionInfo.seller, _auctionInfo.tokenId, 1, "");
			}
		}
		_auctionInfo.isEnd = true;
		delete nftAuctionId[_auctionInfo.nft][_auctionInfo.tokenId];
		emit UpdateAuction(aucId, 0);
	}

	function retrieve(
		address nft,
		uint256 tokenId,
		address to
	) external onlyOwner {
		uint256 aucId = nftAuctionId[nft][tokenId];
		if (aucId > 0) {
			AuctionInfo storage _auctionInfo = auctionList[aucId];
			require(_auctionInfo.buyer == address(0) && block.number > _auctionInfo.endBlock, "sale is not end");
			//only offical auction can retrieve
			require(auctionList[aucId].seller == address(0), "operation is not permit");
			delete nftAuctionId[nft][tokenId];
			_auctionInfo.isEnd = true;
			emit UpdateAuction(aucId, 0);
		}
		IERC1155(nft).safeTransferFrom(address(this), to, tokenId, 1, "");
	}

	// Withdraw EMERGENCY ONLY.
	function emergencyWithdraw(
		address _token,
		address to,
		uint256 _amount
	) external onlyOwner {
		require(to != address(0), "to address is zero");
		IERC20(_token).safeTransfer(to, _amount);
	}

	function onERC1155Received(
		address _operator,
		address _from,
		uint256 _id,
		uint256 _amount,
		bytes calldata _data
	) external returns (bytes4) {
		(uint256 price, uint256 onePrice, uint8 identify, uint256 totalCountdown) = abi.decode(_data, (uint256, uint256, uint8, uint256));
		address seller;
		if (identify == 0) {
			require(_operator == owner(), "SENDER_IS_NOT_OWNER");
		} else {
			seller = _from;
		}
		addAuction(msg.sender, _id, price, onePrice, seller, totalCountdown);
		return ERC1155_RECEIVED_VALUE;
	}

	function onERC1155BatchReceived(
		address _operator,
		address _from,
		uint256[] calldata _ids,
		uint256[] calldata _amounts,
		bytes calldata _data
	) external returns (bytes4) {
		(uint256 price, uint256 onePrice, uint8 identify, uint256 totalCountdown) = abi.decode(_data, (uint256, uint256, uint8, uint256));
		address seller;
		if (identify == 0) {
			require(_operator == owner(), "SENDER_IS_NOT_OWNER");
		} else {
			seller = _from;
		}
		for (uint256 i = 0; i < _ids.length; i++) {
			addAuction(msg.sender, _ids[i], price, onePrice, seller, totalCountdown);
		}
		return ERC1155_BATCH_RECEIVED_VALUE;
	}

	function supportsInterface(bytes4 interfaceID) external view returns (bool) {
		return true;
	}
}
