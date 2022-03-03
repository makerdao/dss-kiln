// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.12;

import "ds-test/test.sol";

import "./DssKilnUNIV2.sol";

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

    DssKilnUNIV2 kiln;

    address dai;
    address mkr;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    uint256 constant WAD = 1e18;

    address constant UNIV2ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        kiln = new DssKilnUNIV2(UNIV2ROUTER);

        kiln.file("lot", 50_000 * WAD);
        kiln.file("hop", 6 hours);

        dai = kiln.DAI();
        mkr = kiln.MKR();
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
