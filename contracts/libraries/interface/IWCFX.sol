pragma solidity =0.5.16;

interface IWCFX {
    function deposit() external payable;
    function depositFor(address recipient, bytes calldata userData) external payable;
    function withdraw(uint256 amount) external;
    function burn(uint256 amount, bytes calldata recipient) external;
}