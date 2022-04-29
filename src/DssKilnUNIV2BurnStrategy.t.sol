// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "ds-test/test.sol";

import "./DssKilnUNIV2BurnStrategy.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external;
}

interface TestGem {
    function totalSupply() external view returns (uint256);
}

contract DssKilnTest is DSTest {
    Hevm hevm;

    DssKilnUNIV2BurnStrategy kiln;

    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant mkr = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    uint256 constant WAD = 1e18;

    address constant UNIV2ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        kiln = new DssKilnUNIV2BurnStrategy(dai, mkr, UNIV2ROUTER);

        kiln.file("lot", 50_000 * WAD);
        kiln.file("hop", 6 hours);

    }

    function mintDai(address usr, uint256 amt) internal {
        hevm.store(
            address(dai),
            keccak256(abi.encode(address(usr), uint(2))),
            bytes32(uint256(amt))
        );
        assertEq(GemLike(dai).balanceOf(address(usr)), amt);
    }

    function testFire() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(GemLike(dai).balanceOf(address(kiln)), 50_000 * WAD);
        uint256 mkrSupply = TestGem(mkr).totalSupply();
        assertTrue(mkrSupply > 0);

        kiln.fire();

        assertEq(GemLike(dai).balanceOf(address(kiln)), 0);
        assertTrue(TestGem(mkr).totalSupply() < mkrSupply);
    }

    function testFireLtLot() public {
        mintDai(address(kiln), 20_000 * WAD);

        assertEq(GemLike(dai).balanceOf(address(kiln)), 20_000 * WAD);

        kiln.fire();

        assertEq(GemLike(dai).balanceOf(address(kiln)), 0);
    }

    function testFireGtLot() public {
        mintDai(address(kiln), 100_000 * WAD);

        assertEq(GemLike(dai).balanceOf(address(kiln)), 100_000 * WAD);

        kiln.fire();

        assertEq(GemLike(dai).balanceOf(address(kiln)), 50_000 * WAD);
    }

    function testFailFireNoBalance() public {
        kiln.fire();
    }

}
