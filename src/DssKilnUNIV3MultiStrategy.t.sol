// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "ds-test/test.sol";

import "./DssKilnUNIV3MultiStrategy.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external;
}

interface TestGem {
    function totalSupply() external view returns (uint256);
}

// https://github.com/Uniswap/v3-periphery/blob/v1.0.0/contracts/lens/Quoter.sol#L106-L122
interface Quoter {
    function quoteExactInput(
        bytes calldata path,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}

contract User {}

contract DssKilnTest is DSTest {
    Hevm hevm;

    DssKilnUNIV3MultiStrategy kiln;

    Quoter quoter;

    bytes path;

    // Dai -> ETH -> MKR
    address constant dai  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant mkr  = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

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
        path = abi.encodePacked(dai, uint24(100), usdc, uint24(500), weth, uint24(3000), mkr);

        kiln = new DssKilnUNIV3MultiStrategy(dai, mkr, UNIV3ROUTER, address(user));

        quoter = Quoter(QUOTER);

        kiln.file("lot", 50_000 * WAD);
        kiln.file("hop", 6 hours);
        kiln.file("path", path);
        kiln.filePrice(1000 * 1e18);  // 1000 Dai/MKR
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
        return quoter.quoteExactInput(path, amtIn);
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

    function testFailFireWhenMaxPriceLtMarket() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(GemLike(dai).balanceOf(address(kiln)), 50_000 * WAD);
        uint256 mkrSupply = TestGem(mkr).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(50_000 * WAD);
        assertTrue(_est > 0);

        assertEq(GemLike(mkr).balanceOf(address(user)), 0);

        kiln.filePrice(100 * WAD); // Expect MKR price 1 dai

        kiln.fire();  // Fail here
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

    function testFireNoPrice() public {
        kiln.filePrice(0);
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
}
