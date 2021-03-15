pragma solidity 0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./SponsorWhitelistControl.sol";
import "./interfaces/IConDragon.sol";
import "./libraries/Tool.sol";

contract CompositeNFT is Ownable, Initializable {
    using SafeMath for uint256;
    SponsorWhitelistControl public constant SPONSOR =
        SponsorWhitelistControl(
            address(0x0888000000000000000000000000000000000001)
        );
    address public genesisNFT;
    address public conDragonNFT;
    mapping(uint256 => bool) public genesisRecord;
    mapping(uint256 => uint8) public specialNumber;
    uint256[] public luckNumbers;
    uint256 public failCount;
    uint256 public lastLuckOnCount;
    uint256 public cat15remain;
    uint256 public cat16remain;
    mapping(uint256 => bool) public luckOnCount;
    mapping(uint256 => uint256) public failProbaility;
    mapping(uint256 => mapping(uint256 => uint256)) public levelMap;
    mapping(address => LastInfo) public userLast;
    struct LastInfo {
        bool isSuccess;
        uint256 tokenId;
    }
    event NewLuckNumber(uint256 failCount, uint256 luckNumber);
    event Composite(
        address _user,
        uint256 _genesisId,
        bool isSuccess,
        uint256 countOrTokenId
    );

    constructor(address _genesisNFT, address _conDragonNFT) public {
        genesisNFT = _genesisNFT;
        conDragonNFT = _conDragonNFT;
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
        cat15remain = 200;
        cat16remain = 200;
    }

    function initialize(
        uint256 _cat15Remain,
        uint256 _cat16Remain,
        uint256[] calldata _luckNumbers,
        uint256 _lastLuckOnCount,
        uint256 _failCount,
        uint256[] calldata _usedGenesis,
        uint256[] calldata _usdeSpecialNumber
    ) external initializer onlyOwner {
        cat15remain = _cat15Remain;
        cat16remain = _cat16Remain;
        luckNumbers = _luckNumbers;
        lastLuckOnCount = _lastLuckOnCount;
        failCount = _failCount;
        for (uint256 i = 0; i < _usedGenesis.length; i++) {
            genesisRecord[_usedGenesis[i]] = true;
        }
        for (uint256 i = 0; i < _usdeSpecialNumber.length; i++) {
            specialNumber[_usdeSpecialNumber[i]] = 2;
        }
    }

    function setRemain(uint256 cat15, uint256 cat16) external onlyOwner {
        cat15remain = cat15;
        cat16remain = cat16;
    }

    function setLevelMap(
        uint256 cat_id,
        uint256[] calldata _weights,
        uint256[] calldata _levels
    ) external onlyOwner {
        for (uint256 i = 0; i < _weights.length; i++) {
            levelMap[cat_id][_weights[i]] = _levels[i];
        }
    }

    function luckNumberLength() public view returns (uint256) {
        return luckNumbers.length;
    }

    function setLuckOnCount(uint256[] calldata _counts, bool[] calldata values)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _counts.length; i++) {
            luckOnCount[_counts[i]] = values[i];
        }
    }

    function setGenesisNFT(address _genesisNFT) external onlyOwner {
        require(_genesisNFT != genesisNFT, "repeat operation!!!");
        genesisNFT = _genesisNFT;
    }

    function setProbaility(
        uint256[] calldata _levels,
        uint256[] calldata _failProbailities
    ) external onlyOwner {
        for (uint256 i = 0; i < _levels.length; i++) {
            failProbaility[_levels[i]] = _failProbailities[i];
        }
    }

    function setConDragonNFT(address _conDragonNFT) external onlyOwner {
        require(_conDragonNFT != conDragonNFT, "repeat operation!!!");
        conDragonNFT = _conDragonNFT;
    }

    function setSpecialNumber(uint256[] calldata _ids) external onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            require(specialNumber[_ids[i]] == 0, "invalid ids");
            specialNumber[_ids[i]] = 1;
        }
    }

    function removeSpecialNumber(uint256[] calldata _ids) external onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            require(specialNumber[_ids[i]] == 1, "invalid ids");
            delete specialNumber[_ids[i]];
        }
    }

    function composite(uint256[] calldata _ids, uint256 genesisId) external {
        address _from = msg.sender;
        if (Tool.isContract(_from)) {
            revert("only wallet");
        }
        IConDragon dragon = IConDragon(conDragonNFT);
        uint256 level =
            levelMap[dragon.categoryOf(_ids[0])][dragon.levelOf(_ids[0])];
        require(level > 0, "level can not empty");
        if (genesisId > 0) {
            require(
                IConDragon(genesisNFT).isTokenOwner(_from, genesisId),
                "genesisId owner not you"
            );
            require(!genesisRecord[genesisId], "genesisId used once");
            require(_ids.length == 13, "length error");
            require(level == 1, "Genesis nft must be used under level 1");
        } else {
            require(_ids.length == 14, "length error");
        }
        uint256[] memory _catIds = new uint256[](_ids.length);
        uint256[] memory _burnIds = new uint256[](_ids.length);
        uint8 _burnLength = 0;
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 catId = dragon.categoryOf(_ids[i]);
            require(dragon.isTokenOwner(_from, _ids[i]), "not token owner");
            require(catId < 15, "catId must less than 15");
            if (i > 0) {
                require(
                    levelMap[catId][dragon.levelOf(_ids[i])] == level,
                    "level must be equal"
                );
                for (uint256 j = 0; j < i; j++) {
                    require(_catIds[j] != catId, "catId Repeat");
                }
            }
            _catIds[i] = catId;
            if (specialNumber[_ids[i]] == 1) {
                specialNumber[_ids[i]] = 2;
            } else {
                _burnIds[_burnLength] = _ids[i];
                _burnLength++;
            }
        }
        (uint256 catId, uint256 burnId) =
            _compositeOrFail(_from, level, _catIds, _ids);
        if (catId > 0) {
            uint256 tokenId =
                dragon.createNFT(
                    _from,
                    catId,
                    _dragon3sWeight(level),
                    1,
                    1,
                    ""
                );
            uint256[] memory burnIds = new uint256[](_burnLength);
            uint256[] memory amounts = new uint256[](_burnLength);
            for (uint256 i = 0; i < _burnLength; i++) {
                burnIds[i] = _burnIds[i];
                amounts[i] = 1;
            }
            dragon.batchBurnNFT(_from, burnIds, amounts);
            LastInfo memory _lastInfo;
            _lastInfo.tokenId = tokenId;
            _lastInfo.isSuccess = true;
            userLast[_from] = _lastInfo;
            if (genesisId > 0) {
                genesisRecord[genesisId] = true;
            }
            emit Composite(_from, genesisId, true, tokenId);
        } else {
            LastInfo memory _lastInfo;
            _lastInfo.tokenId = burnId;
            _lastInfo.isSuccess = false;
            userLast[_from] = _lastInfo;
            emit Composite(_from, genesisId, false, failCount);
        }
    }

    function _compositeOrFail(
        address _from,
        uint256 level,
        uint256[] memory _catIds,
        uint256[] memory _ids
    ) internal returns (uint256 catId, uint256 burnId) {
        if (level == 1) {
            require(
                cat16remain > 0 || cat15remain > 0,
                "level 1 conDragon is no remaining"
            );
        }
        IConDragon dragon = IConDragon(conDragonNFT);
        uint256 random = _seed(_from, 10000);
        if (random < failProbaility[level]) {
            uint256[] memory indexs = new uint256[](_catIds.length);
            bool classC = random.mod(2) == 0;
            uint256 length = 0;
            for (uint256 i = 0; i < _catIds.length; i++) {
                if (_isCatClass(_catIds[i], classC)) {
                    indexs[length] = i;
                    length++;
                }
            }
            burnId = _ids[indexs[random.mod(length)]];
            dragon.burnNFT(_from, burnId, 1);
            failCount++;
            if (luckOnCount[failCount]) {
                uint256 luckNumber =
                    random
                        .mod(failCount.sub(lastLuckOnCount))
                        .add(lastLuckOnCount)
                        .add(1);
                emit NewLuckNumber(failCount, luckNumber);
                luckNumbers.push(luckNumber);
                lastLuckOnCount = failCount;
            }
        } else {
            if (level > 1) {
                catId = random.mod(2) == 1 ? 15 : 16;
            } else if (cat16remain > 0 && cat15remain > 0) {
                catId = random.mod(2) == 1 ? 15 : 16;
                if (catId == 15) {
                    cat15remain = cat15remain.sub(1);
                } else {
                    cat16remain = cat16remain.sub(1);
                }
            } else if (cat15remain > 0) {
                catId = 15;
                cat15remain = cat15remain.sub(1);
            } else {
                catId = 16;
                cat16remain = cat16remain.sub(1);
            }
        }
    }

    function _dragon3sWeight(uint256 level) public pure returns (uint256) {
        if (level == 1) {
            return 1;
        } else if (level == 2) {
            return 3;
        } else if (level == 3) {
            return 21;
        } else if (level == 4) {
            return 210;
        }
    }

    function _isCatClass(uint256 catId, bool classC)
        internal
        view
        returns (bool)
    {
        if (classC) {
            return catId > 0 && catId < 5;
        } else {
            return catId > 4 && catId < 9;
        }
        return false;
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
                            block.coinbase,
                            gasleft(),
                            block.difficulty
                        )
                    )
                ) % _supply
            );
    }
}
