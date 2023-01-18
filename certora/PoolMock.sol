pragma solidity 0.6.12;

interface GemLike {
    function approve(address, uint256) external returns (bool);
}

contract PoolMock {
    address public immutable gem;
    address public immutable usr;
    constructor(address _gem, address _usr) public {
        gem = _gem;
        usr = _usr;
        GemLike(_gem).approve(_usr, type(uint256).max);
    }
}
