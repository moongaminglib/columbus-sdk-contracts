pragma solidity =0.5.16;
pragma experimental ABIEncoderV2;

import "./libraries/Tool.sol";

contract DecodeData {
    function decode(bytes memory _data)
        public
        pure
        returns (string memory, string memory)
    {
        return abi.decode(_data, (string, string));
    }

    function placeId(bytes memory _data) public pure returns (uint256) {
        return Tool.parseDataPlace(_data, 32);
    }
}
