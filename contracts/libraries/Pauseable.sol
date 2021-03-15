pragma solidity >=0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";

contract Pauseable is Ownable{
  bool private _isPause;
  event SetPaused(address indexed from, bool originalPause, bool newPause);
  constructor() internal {
    _isPause = false;
  }
  function getPause() public view returns(bool) {
    return _isPause;
  }

  modifier whenPaused() {
     require(!_isPause, "Pauseable: contract paused");
      _;
  }
  
  function setPause(bool isPause) public onlyOwner {
    emit SetPaused(msg.sender, _isPause, isPause);
    _isPause = isPause;
  }
}