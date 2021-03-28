pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./SponsorWhitelistControl.sol";
import "./libraries/Math.sol";
import "./libraries/Tool.sol";
import "./interfaces/ICustomNFT.sol";
import "./interfaces/IWCFX.sol";
import "./ERC1155/interfaces/IERC1155TokenReceiver.sol";

interface SwapRoute {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract NFTBlindBox is IERC777Recipient, Ownable, IERC1155TokenReceiver {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes4 internal constant ERC1155_RECEIVED_VALUE = 0xf23a6e61;
    bytes4 internal constant ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

    SponsorWhitelistControl public constant SPONSOR = SponsorWhitelistControl(
        address(0x0888000000000000000000000000000000000001)
    );
    IERC1820Registry private _erc1820 = IERC1820Registry(
        0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820
    );
    // keccak256("ERC777TokensRecipient")
    bytes32
        private constant TOKENS_RECIPIENT_INTERFACE_HASH = 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;
    address public nft;
    address public fc;
    address public cMoon;
    address public wcfx;

    uint256 public poolNumerator;
    uint256 public inviterNumerator;

    uint256 public constant totalDenominator = 100;

    struct StageInfo {
        uint256 fcPrice;
        uint256 cMoonPrice;
        uint256 wcfxPrice;
        bool sale;
        uint256 saleHeight;
    }
    mapping(uint256 => uint256[]) private nftIds;
    mapping(address => uint256) public userLatestBuy;
    struct InviteInfo {
        uint256 count;
        uint256 sum;
    }
    mapping(uint256 => StageInfo) public stages;
    mapping(address => InviteInfo) public userInvite;
    mapping(address => address) public inviter;
    mapping(uint256 => uint256) public nftCatId;
    mapping(uint256 => bool) public nftOnSale;
    address[] public fcPaths;
    address[] public cfxPaths;
    address public swapRoute;
    address public pool;
    // calc reward
    address public devAddr;

    // event
    event TokenTransfer(
        address indexed tokenAddress,
        address indexed from,
        uint256 value,
        uint256 stagNum
    );
    event uploadNFTEvent(address indexed from, uint256 count);
    event rewardInvite(address indexed inviter, address from, uint256 amount);
    event rewardPool(address indexed pool, address token, uint256 amount);
    event TokenBuy(
        address indexed to,
        uint256 catId,
        uint256 tokenId,
        uint256 value,
        uint256 stageNum
    );

    constructor(
        address _nft,
        address _devAddr,
        address _fc,
        address[] memory _fcPaths,
        address _cMoon,
        address _wcfx,
        address[] memory _wcfxPaths,
        address _swapRoute,
        address _pool
    ) public {
        nft = _nft;
        fc = _fc;
        fcPaths = _fcPaths;
        cMoon = _cMoon;
        wcfx = _wcfx;
        cfxPaths = _wcfxPaths;
        devAddr = _devAddr;
        swapRoute = _swapRoute;
        pool = _pool;

        poolNumerator = 50;
        inviterNumerator = 1;

        _erc1820.setInterfaceImplementer(
            address(this),
            TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    function setNumerator(uint256 _poolNumerator, uint256 _inviterNumerator)
        external
        onlyOwner
    {
        require(
            _poolNumerator.add(_inviterNumerator) <= totalDenominator,
            "The numerator is greater than the denominator"
        );
        poolNumerator = _poolNumerator;
        inviterNumerator = _inviterNumerator;
    }

    function getNFTLength(uint256 stageNum) public view returns (uint256) {
        return nftIds[stageNum].length;
    }

    function cfxBuy(uint256 stageNum, address _inviter) external payable {
        IWCFX(wcfx).depositFor.value(msg.value)(address(this), "");
        address from = msg.sender;
        uint256 amount = msg.value;
        emit TokenTransfer(wcfx, from, amount, stageNum);
        _inviter = _invite(from, _inviter);
        _cfxBuy(amount, stageNum, from, _inviter);
    }

    function getNFTList(uint256 stageNum, uint256 begin)
        public
        view
        returns (uint256[] memory)
    {
        require(
            begin >= 0 && begin < nftIds[stageNum].length,
            "conDragonMaket: accountList out of range"
        );
        uint256 range = Math.min(nftIds[stageNum].length, begin.add(100));
        uint256[] memory res = new uint256[](range);
        for (uint256 i = begin; i < range; i++) {
            res[i - begin] = nftIds[stageNum][i];
        }
        return res;
    }

    function uploadCatNftsRange(
        uint256 stageNum,
        uint256 start,
        uint256 end,
        uint256 _catId
    ) external onlyOwner {
        require(end > start, "out of range");
        for (uint256 i = start; i < end; i++) {
            require(!nftOnSale[i], "nft already on sale");
            nftIds[stageNum].push(i);
            nftOnSale[i] = true;
            nftCatId[i] = _catId;
        }
        emit uploadNFTEvent(msg.sender, end.sub(start).add(1));
    }

    function uploadCategoryNfts(
        uint256 stageNum,
        uint256[] calldata _ids,
        uint256 _catId
    ) external onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            require(!nftOnSale[_ids[i]], "nft already on sale");
            nftIds[stageNum].push(_ids[i]);
            nftOnSale[_ids[i]] = true;
            nftCatId[_ids[i]] = _catId;
        }
        emit uploadNFTEvent(msg.sender, _ids.length);
    }

    function setSale(
        uint256 stageNum,
        bool sale,
        uint256 _saleHeight
    ) external onlyOwner {
        require(
            stages[stageNum].sale != sale ||
                stages[stageNum].saleHeight != _saleHeight,
            "Repeat operation"
        );
        stages[stageNum].sale = sale;
        stages[stageNum].saleHeight = _saleHeight;
    }

    function setPrices(
        uint256 stageNum,
        uint256 _fcPrice,
        uint256 _cMoonPrice,
        uint256 _wCFXPrice
    ) external onlyOwner {
        StageInfo memory _stageInfo = stages[stageNum];
        _stageInfo.fcPrice = _fcPrice;
        _stageInfo.cMoonPrice = _cMoonPrice;
        _stageInfo.wcfxPrice = _wCFXPrice;
        stages[stageNum] = _stageInfo;
    }

    function setPool(address _pool) external onlyOwner {
        pool = _pool;
    }

    function setNFT(address _nft) external onlyOwner {
        nft = _nft;
    }

    function setSwapRoute(
        address _route,
        address[] calldata _fcPaths,
        address[] calldata _wcfxPaths
    ) external onlyOwner {
        swapRoute = _route;
        fcPaths = _fcPaths;
        cfxPaths = _wcfxPaths;
    }

    // user
    function _buy(uint256 stageNum, address _from)
        internal
        returns (uint256 _tokenId)
    {
        uint256 length = nftIds[stageNum].length;
        require(length > 0, "conDragonMarket: Already sold");
        uint256 _index = _seed(_from, length);
        _tokenId = nftIds[stageNum][_index];
        nftIds[stageNum][_index] = nftIds[stageNum][length - 1];
        nftIds[stageNum].pop();
        nftOnSale[_tokenId] = false;
        uint256 catId = ICustomNFT(nft).categoryOf(_tokenId);
        uint256 _amount = 1;
        if (catId != 0) {
            ICustomNFT(nft).safeTransferFrom(
                address(this),
                _from,
                _tokenId,
                _amount,
                ""
            );
        } else {
            ICustomNFT(nft).createNFTWithId(
                _from,
                _tokenId,
                nftCatId[_tokenId],
                1,
                1,
                1,
                ""
            );
        }
        userLatestBuy[_from] = _tokenId;
        emit TokenBuy(_from, nftCatId[_tokenId], _tokenId, _amount, stageNum);
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

    // limit nft token
    function retrieve(uint256 stageNum, uint256[] calldata _ids)
        external
        onlyOwner
    {
        uint256[] memory _nftIds = nftIds[stageNum];
        uint256 length = _nftIds.length;
        for (uint256 i = 0; i < _ids.length; i++) {
            require(nftOnSale[_ids[i]], "nft not on sale");
            uint256 _tokenId = _ids[i];
            uint256 _index = uint256(~0);
            for (uint256 j = 0; j < length; j++) {
                if (_nftIds[j] == _tokenId) {
                    _index = j;
                    break;
                }
            }
            require(_index != uint256(~0), "not found nft");
            _nftIds[_index] = _nftIds[length - 1];
            nftOnSale[_tokenId] = false;
            length--;
        }
        nftIds[stageNum] = _nftIds;
        nftIds[stageNum].length = length;
    }

    function clearUp(uint256 stageNum) external onlyOwner {
        uint256[] memory _nftIds = nftIds[stageNum];
        uint256 length = _nftIds.length;
        for (uint256 i = 0; i < length; i++) {
            nftOnSale[_nftIds[i]] = false;
        }
        nftIds[stageNum].length = 0;
    }

    function forceRetrieve(
        address _token,
        address _to,
        uint256[] calldata _ids
    ) external onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            _safeNFTTransfer(_token, _to, _ids[i]);
        }
    }

    function _seed(address _user, uint256 _supply)
        internal
        view
        returns (uint256)
    {
        return
            uint256(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            _user,
                            block.number,
                            block.timestamp,
                            block.difficulty
                        )
                    )
                ) % _supply
            );
    }

    function _safeNFTTransfer(
        address _token,
        address _to,
        uint256 _id
    ) internal {
        ICustomNFT(_token).safeTransferFrom(address(this), _to, _id, 1, "");
    }

    function _cMoonBuy(
        uint256 amount,
        uint256 stageNum,
        address from,
        address _inviter
    ) internal checkBuy(stageNum, from) {
        {
            uint256 cMoonPrice = stages[stageNum].cMoonPrice;
            require(
                cMoonPrice > 0 && amount >= cMoonPrice,
                "conDragonMarket:amount less fc price"
            );
            uint256 count = amount.div(cMoonPrice);
            require(
                count.mul(cMoonPrice) == amount,
                "conDragonMarket:amount error"
            );
            for (uint256 i = 0; i < count; i++) {
                _buy(stageNum, from);
            }
        }
        uint256 swapAmount;
        if (_inviter != address(0)) {
            swapAmount = amount.mul(poolNumerator.add(inviterNumerator)).div(
                totalDenominator
            );
        } else {
            swapAmount = amount.mul(poolNumerator).div(totalDenominator);
        }
        IERC20(cMoon).safeTransfer(devAddr, amount.sub(swapAmount));
        _reward(_inviter, from, swapAmount);
    }

    function _fcBuy(
        uint256 amount,
        uint256 stageNum,
        address from,
        address _inviter
    ) internal checkBuy(stageNum, from) {
        {
            uint256 fcPrice = stages[stageNum].fcPrice;
            require(
                fcPrice > 0 && amount >= fcPrice,
                "conDragonMarket:amount less fc price"
            );
            uint256 count = amount.div(fcPrice);
            require(
                count.mul(fcPrice) == amount,
                "conDragonMarket:amount error"
            );
            for (uint256 i = 0; i < count; i++) {
                _buy(stageNum, from);
            }
        }
        uint256 swapAmount;
        if (_inviter != address(0)) {
            swapAmount = amount.mul(poolNumerator.add(inviterNumerator)).div(
                totalDenominator
            );
        } else {
            swapAmount = amount.mul(poolNumerator).div(totalDenominator);
        }
        IERC20(fc).safeApprove(swapRoute, swapAmount);
        uint256[] memory amounts = SwapRoute(swapRoute)
            .swapExactTokensForTokens(
            swapAmount,
            0,
            fcPaths,
            address(this),
            now + 1800
        );
        IERC20(fc).safeTransfer(devAddr, amount.sub(swapAmount));
        _reward(_inviter, from, amounts[amounts.length - 1]);
    }

    modifier checkBuy(uint256 stageNum, address from) {
        require(tx.origin == from, "ConDragonSale: only wallet");
        if (Tool.isContract(from)) {
            revert("ConDragonSale: only wallet");
        }
        require(
            stages[stageNum].sale &&
                (stages[stageNum].saleHeight == 0 ||
                    block.number >= stages[stageNum].saleHeight),
            "stage not ready to sale"
        );
        _;
    }

    function _cfxBuy(
        uint256 amount,
        uint256 stageNum,
        address from,
        address _inviter
    ) internal checkBuy(stageNum, from) {
        {
            uint256 wcfxPrice = stages[stageNum].wcfxPrice;
            require(
                wcfxPrice > 0 && amount >= wcfxPrice,
                "amount less wcfx price"
            );
            uint256 count = amount.div(wcfxPrice);
            require(
                count.mul(wcfxPrice) == amount,
                "conDragonMarket:amount error"
            );
            for (uint256 i = 0; i < count; i++) {
                _buy(stageNum, from);
            }
        }
        uint256 swapAmount;
        if (_inviter != address(0)) {
            swapAmount = amount.mul(poolNumerator.add(inviterNumerator)).div(
                totalDenominator
            );
        } else {
            swapAmount = amount.mul(poolNumerator).div(totalDenominator);
        }
        IERC20(wcfx).safeApprove(swapRoute, swapAmount);
        uint256[] memory amounts = SwapRoute(swapRoute)
            .swapExactTokensForTokens(
            swapAmount,
            0,
            cfxPaths,
            address(this),
            now + 1800
        );
        IERC20(wcfx).safeTransfer(devAddr, amount.sub(swapAmount));
        _reward(_inviter, from, amounts[amounts.length - 1]);
    }

    function _reward(
        address _inviter,
        address from,
        uint256 total
    ) internal {
        uint256 inviterAmount = 0;
        if (_inviter != address(0)) {
            inviterAmount = total.mul(inviterNumerator).div(
                inviterNumerator.add(poolNumerator)
            );
        }
        uint256 pool_amount = total.sub(inviterAmount);
        emit rewardPool(pool, cMoon, pool_amount);
        if (_inviter != address(0)) {
            IERC20(cMoon).safeTransfer(_inviter, inviterAmount);
            emit rewardInvite(_inviter, from, inviterAmount);
            userInvite[_inviter].sum = userInvite[_inviter].sum.add(
                inviterAmount
            );
        }
        IERC777(cMoon).send(pool, pool_amount, "02");
    }

    function _invite(address from, address _inviter)
        internal
        returns (address)
    {
        address reward_to = inviter[from];
        if (reward_to == address(0) && _inviter != address(0)) {
            reward_to = _inviter;
            inviter[from] = reward_to;
            userInvite[reward_to].count++;
        }
        require(reward_to != from, "invite can not be self");
        return reward_to;
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
        if (userData.length != 64) {
            return;
        }
        require(operator == from, "ConDragonSale: only wallet");
        address _inviter;
        uint256 stageNum;
        (stageNum, _inviter) = abi.decode(userData, (uint256, address));
        emit TokenTransfer(msg.sender, from, amount, stageNum);
        _inviter = _invite(from, _inviter);
        if (msg.sender == cMoon) {
            _cMoonBuy(amount, stageNum, from, _inviter);
        } else if (msg.sender == fc) {
            _fcBuy(amount, stageNum, from, _inviter);
        } else if (msg.sender == wcfx) {
            _cfxBuy(amount, stageNum, from, _inviter);
        } else {
            revert("pay token is not correct");
        }
    }

    function setDevAddr(address _devAddr) external onlyOwner {
        devAddr = _devAddr;
    }

    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bytes4) {
        return ERC1155_RECEIVED_VALUE;
    }

    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external returns (bytes4) {
        return ERC1155_BATCH_RECEIVED_VALUE;
    }

    function supportsInterface(bytes4 interfaceID)
        external
        view
        returns (bool)
    {
        return true;
    }
}
