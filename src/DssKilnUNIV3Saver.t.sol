// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";

import "./DssKilnUNIV3Saver.sol";

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
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

contract User {}

contract DssKilnTest is DSTest {
    Hevm hevm;

    DssKilnUNIV3Saver kiln;

    Quoter quoter;

    address dai;
    address mkr;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    uint256 constant WAD = 1e18;

    address constant UNIV3ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    User user;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        user = new User();
        kiln = new DssKilnUNIV3Saver(UNIV3ROUTER, address(user));

        quoter = Quoter(QUOTER);

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

        assertEq(GemLike(mkr).balanceOf(address(user)), 0);

        kiln.fire();

        assertTrue(GemLike(dai).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(mkr).balanceOf(address(user)), _est);
    }

    // Lot is 50k, ensure we can still fire if balance is lower than lot
    function testFireLtLot() public {
        mintDai(address(kiln), 20_000 * WAD);

        assertEq(GemLike(dai).balanceOf(address(kiln)), 20_000 * WAD);
        uint256 mkrSupply = TestGem(mkr).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(20_000 * WAD);
        assertTrue(_est > 0);

        assertEq(GemLike(mkr).balanceOf(address(user)), 0);

        kiln.fire();

        assertEq(GemLike(dai).balanceOf(address(kiln)), 0);
        assertEq(TestGem(mkr).totalSupply(), mkrSupply); // not burned
        assertEq(GemLike(mkr).balanceOf(address(user)), _est);
    }

    // Ensure we only sell off the lot size
    function testFireGtLot() public {
        mintDai(address(kiln), 100_000 * WAD);

        assertEq(GemLike(dai).balanceOf(address(kiln)), 100_000 * WAD);

        uint256 _est = estimate(kiln.lot());
        assertTrue(_est > 0);

        kiln.fire();

        // Due to liquidity constrants, not all of the tokens may be sold
        assertTrue(GemLike(dai).balanceOf(address(kiln)) >= 50_000 * WAD);
        assertTrue(GemLike(dai).balanceOf(address(kiln)) < 100_000 * WAD);
        assertEq(GemLike(mkr).balanceOf(address(user)), _est);
    }


    function testBurnMulti() public {
        mintDai(address(kiln), 100_000 * WAD);

        kiln.file("lot", 50 * WAD); // Use a smaller amount due to slippage limits

        kiln.fire();

        hevm.warp(block.timestamp + 6 hours);

        kiln.fire();
    }

    function testFailFireNoBalance() public {
        if (GemLike(dai).balanceOf(address(kiln)) == 0) {
            kiln.fire(); // fail here for green light
        }
        // If balance is gt 0 test will fail here
    }
}
