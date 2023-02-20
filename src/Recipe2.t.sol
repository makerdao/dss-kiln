// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "./Recipe2.sol";

import "src/uniV2/UniswapV2Library.sol";
import "src/uniV2/IUniswapV2Pair.sol";

interface TestGem {
    function totalSupply() external view returns (uint256);
}

// https://github.com/Uniswap/v3-periphery/blob/v1.0.0/contracts/lens/UNIV3Quoter.sol#L106-L122
interface UNIV3Quoter { // TODO: handle caps
    function quoteExactInput(
        bytes calldata path,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}

interface ExtendedUNIV2Router is UniswapV2Router02Like {
    function factory() external view returns (address);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external returns (uint256 amountOut);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface UniswapV2FactoryLike {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

}

interface UniswapV2PairLike {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract User {}

contract KilnTest is Test {

    using UniswapV2Library for *;

    Recipe2 kiln;
    UNIV3Quoter univ3Quoter;
    User user;

    bytes path;

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MKR  = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    uint256 constant WAD = 1e18;

    address constant UNIV2ROUTER   = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant UNIV2DAIMKRLP = 0x517F9dD285e75b599234F7221227339478d0FcC8;

    address constant UNIV3ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3QUOTER  = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant UNIV3FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    event File(bytes32 indexed what, bytes data);
    event File(bytes32 indexed what, uint256 data);

    function setUp() public {
        user = new User();
        path = abi.encodePacked(DAI, uint24(100), USDC, uint24(500), WETH, uint24(3000), MKR);

        kiln = new Recipe2(DAI, MKR, UNIV2ROUTER, UNIV3ROUTER, address(user));
        univ3Quoter = UNIV3Quoter(UNIV3QUOTER);

        kiln.file("lot", 15_000 * WAD);
        kiln.file("hop", 6 hours);
        kiln.file("path", path);

        kiln.file("yen", 50 * WAD / 100); // Insist on very little on default
        kiln.file("zen", 50 * WAD / 100); // Allow large deviations by default

        topUpLiquidity();
    }


    function mintDai(address usr, uint256 amt) internal {
        deal(DAI, usr, amt);
        assertEq(GemLike(DAI).balanceOf(address(usr)), amt);
    }

    function topUpLiquidity() internal {
        uint256 daiAmt = 1_000_000 * WAD; // TODO: need to start initial liquidity more wisely - first change price, then deposit smaller amount, then start with small lot
        uint256 mkrAmt = 1000 * WAD;

        uint reserveA;
        uint reserveB;
        (address token0,) = UniswapV2Library.sortTokens(DAI, MKR);
        address pairToken = UniswapV2Library.pairFor(ExtendedUNIV2Router(UNIV2ROUTER).factory(), DAI, MKR);

        (uint reserve0, uint reserve1,) = UniswapV2PairLike(pairToken).getReserves();
        (reserveA, reserveB) = DAI == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        mkrAmt = daiAmt / (reserveA / reserveB) - 10 * WAD;

        deal(DAI, address(this), daiAmt);
        deal(MKR, address(this), mkrAmt);

        GemLike(DAI).approve(UNIV2ROUTER, daiAmt);
        GemLike(MKR).approve(UNIV2ROUTER, mkrAmt);

        UniswapV2Router02Like(UNIV2ROUTER).addLiquidity(
            MKR,
            DAI,
            mkrAmt,
            daiAmt,
            0,
            0,
            address(this),
            block.timestamp);

        assertGt(GemLike(pairToken).balanceOf(address(this)), 0);
    }

    /*
    function estimate(uint256 amtIn) internal returns (uint256 amtOut) {
        return univ3Quoter.quoteExactInput(path, amtIn);
    }

    function swap(address gem, uint256 amount) internal {
        GemLike(gem).approve(kiln.uniV3Router(), amount);

        bytes memory _path;
        if (gem == DAI) {
            _path = abi.encodePacked(DAI, uint24(100), USDC, uint24(500), WETH, uint24(3000), MKR);
        } else {
            _path = abi.encodePacked(MKR, uint24(3000), WETH, uint24(500), USDC, uint24(100), DAI);
        }

        ExactInputParams memory params = ExactInputParams(
            _path,
            address(this),       // recipient
            block.timestamp,     // deadline
            amount,              // amountIn
            0                    // amountOutMinimum
        );

        SwapRouterLike(kiln.uniV3Router()).exactInput(params);
    }
    */






    /*
    function testFilePath() public {
        path = abi.encodePacked(DAI, uint24(100), USDC);
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("path"), path);
        kiln.file("path", path);
        assertEq0(kiln.path(), path);
    }

    function testFileYen() public {
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("yen"), 42);
        kiln.file("yen", 42);
        assertEq(kiln.yen(), 42);
    }

    function testFileScope() public {
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("scope"), 314);
        kiln.file("scope", 314);
        assertEq(kiln.scope(), 314);
    }

    function testFileZeroScope() public {
        vm.expectRevert("KilnUniV3/zero-scope");
        kiln.file("scope", 0);
    }

    function testFileScopeTooLarge() public {
        vm.expectRevert("KilnUniV3/scope-overflow");
        kiln.file("scope", uint32(type(int32).max) + 1);
    }

    function testFileBytesUnrecognized() public {
        vm.expectRevert("KilnUniV3/file-unrecognized-param");
        kiln.file("nonsense", bytes(""));
    }

    function testFileUintUnrecognized() public {
        vm.expectRevert("KilnBase/file-unrecognized-param");
        kiln.file("nonsense", 23);
    }

    function testFilePathNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.file("path", path);
    }

    function testFileYenNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.file("yen", 42);
    }

    function testFileScopeNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.file("scope", 413);
    }
    */

    function testFire1() public { // TODO: can remove once we have the other tests?
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(GemLike(UNIV2DAIMKRLP).balanceOf(address(user)), 0);
        assertEq(GemLike(DAI).balanceOf(address(kiln)),50_000 * WAD);

        kiln.fire();

        assertGt(GemLike(UNIV2DAIMKRLP).balanceOf(address(user)), 0);
        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(kiln)), 0);
    }


    /*

    Given a reference TWAP out amount, we want to test the following scenarios.
    Note that `Higher` stands for higher out amount than the reference, while `Lower` stands for lower out amount than the reference.

    testFire
    ├── Univ3Higher
    │         ├── YenAllows (1.00)
    │         │         ├── Univ2Higher
    │         │         │         ├── ZenAllows (0.95)
    │         │         │         └── ZenBlocks (1.0)
    │         │         └── Univ2Lower
    │         │             ├── ZenAllows (0.95)
    │         │             └── ZenBlocks (1.00)
    │         └── YenBlocks (1.05)
    └── Univ3Lower
              ├── YenAllows (0.95)
              │         ├── Univ2Higher
              │         │         ├── ZenAllows (0.95)
              │         │         └── ZenBlocks (1.00)
              │         └── Univ2Lower
              │             ├── ZenAllows (0.95)
              │             └── ZenBlocks (1.00)
              └── YenBlocks (1.00)
    */

    function getRefOutAMount(uint256 amountIn) internal returns (uint256) {
        return kiln.quote(kiln.path(), amountIn, uint32(kiln.scope()));
    }



    function changeUniv3Price(uint256 amountIn, uint256 refOutAmount, bool reachHigher) internal {
        uint256 current = univ3Quoter.quoteExactInput(path, amountIn);
        console.log("current: %s", current);

        // TODO: change actor who does this to address(123) or something
        if (reachHigher) {
            while (current < refOutAmount) {

                // trade mkr to dai
                uint256 mkrAmount = 20 * WAD;
                bytes memory path_ = abi.encodePacked(MKR, uint24(3000), WETH, uint24(500), USDC, uint24(100), DAI);
                deal(MKR, address(this), mkrAmount);
                GemLike(MKR).approve(UNIV3ROUTER, mkrAmount);
                    SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
                    path:             path_,
                    recipient:        address(this),
                    deadline:         block.timestamp,
                    amountIn:         mkrAmount,
                    amountOutMinimum: 0
                });
                SwapRouterLike(UNIV3ROUTER).exactInput(params);

                current = univ3Quoter.quoteExactInput(path, amountIn);
                console.log("current: %s", current);
            }
        } else {
            while (current > refOutAmount) {

                // trade dai mkr
                uint256 daiAmount = 20_000 * WAD;
                deal(DAI, address(this), daiAmount);
                GemLike(DAI).approve(UNIV3ROUTER, daiAmount);
                SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
                path:             path,
                recipient:        address(this),
                deadline:         block.timestamp,
                amountIn:         daiAmount,
                amountOutMinimum: 0
                });
                SwapRouterLike(UNIV3ROUTER).exactInput(params);

                current = univ3Quoter.quoteExactInput(path, amountIn);
                console.log("current: %s", current);
            }
        }
    }

    function getUniv2AmountOut(uint256 amountIn) internal returns (uint256 amountOut) {
        uint reserveA;
        uint reserveB;

        (address token0,) = UniswapV2Library.sortTokens(DAI, MKR);
        address pairToken = UniswapV2Library.pairFor(    ExtendedUNIV2Router(UNIV2ROUTER).factory(), DAI, MKR);

        console.log("pairToken: %s", pairToken);
        (uint reserve0, uint reserve1,) = UniswapV2PairLike(pairToken).getReserves();
        (reserveA, reserveB) = DAI == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        console.log("reserveA: %s", reserveA);
        console.log("reserveB: %s", reserveB);

        amountOut = ExtendedUNIV2Router(UNIV2ROUTER).getAmountOut(amountIn, reserveA, reserveB);
    }

    function changeUniv2Price(uint256 amountIn, uint256 refOutAmount, bool reachHigher) internal {

        uint256 current = getUniv2AmountOut(amountIn);
        console.log("refOutAmount: %s", refOutAmount);
        console.log("current: %s", current);


        // TODO: change actor who does this to address(123) or something
        if (reachHigher) {
            while (current < refOutAmount) {

                // trade mkr to dai

                address[] memory _path = new address[](2);
                _path[0] = MKR;
                _path[1] = DAI;

                uint256 mkrAmount = 1 * WAD / 10;
                deal(MKR, address(this), mkrAmount);
                GemLike(MKR).approve(UNIV2ROUTER, mkrAmount);
                ExtendedUNIV2Router(UNIV2ROUTER).swapExactTokensForTokens(
                    mkrAmount,          // amountIn
                    0,                 // amountOutMin
                    _path,             // path
                    address(this),     // to
                    block.timestamp
                );  // deadline

                current = getUniv2AmountOut(amountIn);
                console.log("current: %s refOutAmount: %s", current, refOutAmount);
            }
        } else {
            while (current > refOutAmount) {

                // trade dai to mkr
                address[] memory _path = new address[](2);
                _path[0] = DAI;
                _path[1] = MKR;

                uint256 daiAmount = 1000 * WAD;
                deal(DAI, address(this), daiAmount);
                GemLike(DAI).approve(UNIV2ROUTER, daiAmount);
                ExtendedUNIV2Router(UNIV2ROUTER).swapExactTokensForTokens(
                    daiAmount,          // amountIn
                    0,                 // amountOutMin
                    _path,             // path
                    address(this),     // to
                    block.timestamp
                );  // deadline

                current = getUniv2AmountOut(amountIn);
                console.log("current: %s", current);            }
        }
    }


    function testFireUniv3HigherYenAllowsUniv2HigherZenAllows() public {
        // get ref price
        uint256 ref = getRefOutAMount(20_000 * WAD);
        console.log("ref: %s", ref);

        // drive up univ3 out amount
        changeUniv3Price(20_000 * WAD, ref, true);

        // set yen to 1.00
        kiln.file("yen", 100 * WAD / 100);

        // drive up univ2 out amount
        changeUniv2Price(20_000 * WAD, ref, true);

        // set zen to 0.95
        kiln.file("zen", 95 * WAD / 100);

        // TODO: this currently fail
        // since there's almost no liquidity need to make sure when driving price up/dpwn that the price will be very close to the ref
        // also need to consider seeding with small amount of initial liquidity
        mintDai(address(kiln), 50_000 * WAD);
        kiln.fire();

        // fire
        // check success

    }


    function testFireAfterLowTwap() public {}
    function testFireAfterHighTwap() public {}



    /*
    function testFireYenMuchLessThanTwap() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 50_000 * WAD);
        uint256 mkrSupply = TestGem(MKR).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(50_000 * WAD);
        assertTrue(_est > 0);

        assertEq(GemLike(MKR).balanceOf(address(user)), 0);

        kiln.file("yen", 80 * WAD / 100);
        kiln.fire();

        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(user)), _est);
    }

    function testFireYenMuchMoreThanTwap() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 50_000 * WAD);
        uint256 mkrSupply = TestGem(MKR).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(50_000 * WAD);
        assertTrue(_est > 0);

        assertEq(GemLike(MKR).balanceOf(address(user)), 0);

        kiln.file("yen", 120 * WAD / 100);
        // https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRouter.sol#L165
        vm.expectRevert("Too little received");
        kiln.fire();
    }

    function testFireYenZero() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 50_000 * WAD);
        uint256 mkrSupply = TestGem(MKR).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(50_000 * WAD);
        assertTrue(_est > 0);

        assertEq(GemLike(MKR).balanceOf(address(user)), 0);

        kiln.file("yen", 0);
        kiln.fire();

        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(user)), _est);
    }

    // Lot is 50k, ensure we can still fire if balance is lower than lot
    function testFireLtLot() public {
        mintDai(address(kiln), 20_000 * WAD);

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 20_000 * WAD);
        uint256 mkrSupply = TestGem(MKR).totalSupply();
        assertTrue(mkrSupply > 0);

        uint256 _est = estimate(20_000 * WAD);
        assertTrue(_est > 0);

        assertEq(GemLike(MKR).balanceOf(address(user)), 0);

        kiln.fire();

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 0);
        assertEq(TestGem(MKR).totalSupply(), mkrSupply);
        assertEq(GemLike(MKR).balanceOf(address(user)), _est);
    }

    // Ensure we only sell off the lot size
    function testFireGtLot() public {
        mintDai(address(kiln), 100_000 * WAD);

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 100_000 * WAD);

        uint256 _est = estimate(kiln.lot());
        assertTrue(_est > 0);

        kiln.fire();

        // Due to liquidity constrants, not all of the tokens may be sold
        assertTrue(GemLike(DAI).balanceOf(address(kiln)) >= 50_000 * WAD);
        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 100_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(user)), _est);
    }

    function testFireMulti() public {
        mintDai(address(kiln), 100_000 * WAD);

        kiln.file("lot", 50 * WAD); // Use a smaller amount due to slippage limits

        kiln.fire();

        skip(6 hours);

        kiln.fire();
    }

    function testFireAfterLowTwap() public {
        mintDai(address(this), 11_000_000 * WAD); // funds for manipulating prices
        mintDai(address(kiln), 1_000_000 * WAD);

        kiln.file("hop", 0 hours); // for convenience allow firing right away
        kiln.file("scope", 1 hours);
        kiln.file("yen", 120 * WAD / 100); // only swap if price rose by 20% vs twap

        uint256 mkrBefore = GemLike(MKR).balanceOf(address(this));

        // drive down MKR out amount with big DAI->MKR swap
        swap(DAI, 10_000_000 * WAD);

        // make sure twap measures low MKR out amount at the beginning of the hour (by making small swap)
        vm.roll(block.number + 1);
        swap(DAI, WAD / 100);

        // let 1 hour almost pass
        skip(1 hours - 1 seconds);

        // make sure twap measures low MKR out amount at the end of the hour (by making small swap)
        vm.roll(block.number + 1);
        swap(DAI, WAD / 100);

        // fire should fail for low MKR out amount
        // https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRouter.sol#L165
        vm.expectRevert("Too little received");
        kiln.fire();

        // drive MKR out amount back up
        swap(MKR, GemLike(MKR).balanceOf(address(this)) - mkrBefore);

        // fire should succeed after MKR amount rose vs twap
        kiln.fire();
    }

    function testFireAfterHighTwap() public {
        mintDai(address(this), 11_000_000 * WAD); // funds for manipulating prices
        mintDai(address(kiln), 1_000_000 * WAD);

        kiln.file("hop", 0 hours); // for convenience allow firing right away
        kiln.file("scope", 1 hours);
        kiln.file("yen", 80 * WAD / 100); // allow swap even if price fell by 20% vs twap

        // make sure twap measures regular MKR out amount at the beginning of the hour (by making small swap)
        vm.roll(block.number + 1);
        swap(DAI, WAD / 100);

        // let 1 hour almost pass
        skip(1 hours - 1 seconds);

        // make sure twap measures regular MKR out amount at the end of the hour (by making small swap)
        vm.roll(block.number + 1);
        swap(DAI, WAD / 100);

        // fire should succeed for low yen before any price manipulation
        kiln.fire();

        // drive down MKR out amount with big DAI->MKR swap
        swap(DAI, 10_000_000 * WAD);

        // fire should fail when low MKR amount
        // https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRouter.sol#L165
        vm.expectRevert("Too little received");
        kiln.fire();
    }

    function testFactoryDerivedFromRouter() public {
        assertEq(SwapRouterLike(UNIV3ROUTER).factory(), UNIV3FACTORY);
    }
    */
}
