pragma solidity =0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

library Tool {
    using SafeMath for uint256;
    using Address for address;

    function isContract(address _addr) internal view returns(bool){
        if(_addr.isContract()){
            return true;
        }

        // conflux feature
        bytes memory b = _addressToBytes(_addr);
        bytes memory _before = _addressToBytes(_addr);
        b[0] = b[0] & 0x0F;
        b[0] = b[0] | 0x80;

        if(_before[0] == b[0]){
             return true;
        }else{
             return false;
        }
    }

    // nft address tokenId
    function parseDataBuy(bytes memory input, uint256 paramAddr, uint256 paramInt) internal pure returns(address a1, uint256 a2){
        uint256 addrLen = paramAddr;
        uint256 intLen = paramInt;
        uint256 startPos = 1;
        bytes memory _a1 = new bytes(addrLen);
        for(uint i = startPos; i < startPos + addrLen; i ++){
            _a1[i - startPos] = input[i];
        }
        a1 = _bytesToAddress(_a1);

        bytes memory _a2 = new bytes(intLen);
        for(uint i = startPos + addrLen; i < startPos + addrLen + intLen; i ++){
          _a2[i - startPos - addrLen] = input[i];
        }

        a2 = _toUint(_a2);
    }

    function parseDataPlace(bytes memory input, uint256 paramInt) internal pure returns(uint256 a2){
        uint256 intLen = paramInt;
        uint256 startPos = 1;
        bytes memory _a2 = new bytes(intLen);
        for(uint i = startPos; i < startPos + intLen; i ++){
          _a2[i - startPos] = input[i];
        }

        a2 = _toUint(_a2);
    }

    function _toUint(bytes memory input) internal pure returns (uint256){
        uint256 x;
        assembly {
            x := mload(add(input, add(0x20, 0)))
        }

        return x;
    }

    function _bytesToAddress(bytes memory bys) internal pure returns(address){
        address addr;
        assembly {
            addr := mload(add(bys, 20))
        }

        return addr;
    }


    function _addressToBytes(address a) internal pure returns (bytes memory) {
        return abi.encodePacked(a);
    }
}
