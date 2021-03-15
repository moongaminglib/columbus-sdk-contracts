pragma solidity 0.5.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/interface/IDragon.sol";

contract BatchWapper {
    function getBalance(address _token, address[] memory users)
        public
        view
        returns (uint256[] memory)
    {
        require(users.length > 0, "length is zero");
        uint256[] memory balances = new uint256[](users.length);
        IERC20 token = IERC20(_token);
        for (uint256 i = 0; i < users.length; i++) {
            balances[i] = token.balanceOf(users[i]);
        }
        return balances;
    }

    function getOwner(address nft, uint256[] memory _ids)
        public
        view
        returns (address[] memory)
    {
        require(_ids.length > 0, "length is zero");
        address[] memory owners = new address[](_ids.length);
        IDragon _dragon = IDragon(nft);
        for (uint256 i = 0; i < _ids.length; i++) {
            address[] memory _owners = _dragon.ownerOf(_ids[i]);
            if (_owners.length > 0) {
                owners[i] = _owners[0];
            }
        }
        return owners;
    }
}
