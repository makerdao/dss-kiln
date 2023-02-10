pragma solidity 0.6.12;

interface GemLike {
    function transferFrom(address, address, uint256) external returns (bool);
}

contract PoolMock {
    address public immutable dai;
    address public immutable gem;
    constructor(address _dai, address _gem) public {
        dai = _dai;
        gem = _gem;
    }

    function swap(uint256 amount) external returns (uint256 swapped) {
        GemLike(dai).transferFrom(msg.sender, address(this), amount);
        GemLike(gem).transferFrom(address(this), msg.sender, amount);
        swapped = amount;
    }
}
