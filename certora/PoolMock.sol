pragma solidity 0.6.12;

interface GemLike {
    function transferFrom(address, address, uint256) external returns (bool);
}

contract PoolMock {
    address public immutable dai;
    address public immutable token;
    constructor(address _dai, address _token) public {
        dai = _dai;
        token = _token;
    }

    function swap(uint256 amount) external returns (uint256 swapped) {
        GemLike(dai).transferFrom(msg.sender, address(this), amount);
        GemLike(token).transferFrom(address(this), msg.sender, amount);
        swapped = amount;
    }
}
