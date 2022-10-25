// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.14;

import "ds-test/test.sol";

import "./DssKilnUNIV3BurnStrategy.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external;
}

interface TestGem {
    function totalSupply() external view returns (uint256);
}

interface Quoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24  fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}


contract DssKilnTest is DSTest {
    Hevm hevm;

    DssKilnUNIV3BurnStrategy kiln;

    Quoter quoter;

    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant mkr = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    uint256 constant WAD = 1e18;

    address constant UNIV3ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        kiln = new DssKilnUNIV3BurnStrategy(dai, mkr, UNIV3ROUTER, 3000);

        quoter = Quoter(QUOTER);

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

    function estimate(uint256 amtIn) internal returns (uint256 amtOut) {
        return quoter.quoteExactInputSingle(dai, mkr, 3000, amtIn, 0);
    }

    function testFire() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(GemLike(dai).balanceOf(address(kiln)), 50_000 * WAD);
        uint256 mkrSupply = TestGem(mkr).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(50_000 * WAD);
        assertTrue(_est > 0);

        kiln.fire();

        // Due to liquidity constrants, not all of the tokens may be sold
        assertTrue(GemLike(dai).balanceOf(address(kiln)) >= 0);
        assertTrue(TestGem(mkr).totalSupply() < mkrSupply);
        assertEq(TestGem(mkr).totalSupply(), mkrSupply - _est);
    }

    function testFireLtLot() public {
        uint256 smallBalance = 100 * WAD;
        mintDai(address(kiln), smallBalance);

        assertEq(GemLike(dai).balanceOf(address(kiln)), smallBalance);
        uint256 mkrSupply = TestGem(mkr).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(smallBalance);
        assertTrue(_est > 0);

        kiln.fire();

        assertEq(GemLike(dai).balanceOf(address(kiln)), 0);
        assertTrue(TestGem(mkr).totalSupply() < mkrSupply);
        assertEq(TestGem(mkr).totalSupply(), mkrSupply - _est);
    }

    function testFireGtLot() public {
        mintDai(address(kiln), 100_000 * WAD);

        assertEq(GemLike(dai).balanceOf(address(kiln)), 100_000 * WAD);
        uint256 mkrSupply = TestGem(mkr).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(kiln.lot());
        assertTrue(_est > 0);

        kiln.fire();

        // Due to liquidity constrants, not all of the tokens may be sold
        assertTrue(GemLike(dai).balanceOf(address(kiln)) >= 50_000 * WAD);
        assertTrue(TestGem(mkr).totalSupply() < mkrSupply);
        assertEq(TestGem(mkr).totalSupply(), mkrSupply - _est);
    }

    function testBurnMulti() public {
        mintDai(address(kiln), 100_000 * WAD);

        kiln.file("lot", 50 * WAD); // Use a smaller amount due to slippage limits

        kiln.fire();

        hevm.warp(block.timestamp + 6 hours);

        kiln.fire();
    }

    function testFailFireNoBalance() public {
        kiln.fire();
    }

}
