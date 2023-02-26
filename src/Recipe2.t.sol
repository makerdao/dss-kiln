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
import "src/Recipe2.sol";
import "src/QuoterTwap.sol";

import "src/uniV2/UniswapV2Library.sol";
import "src/uniV2/IUniswapV2Pair.sol";

interface TestGem {
    function totalSupply() external view returns (uint256);
}

// https://github.com/Uniswap/v3-periphery/blob/v1.0.0/contracts/lens/UNIV3Quoter.sol#L106-L122
interface Univ3Quoter {
    function quoteExactInput(bytes calldata path, uint256 amountIn) external returns (uint256 amountOut);
}

// https://github.com/Uniswap/v2-periphery/blob/dda62473e2da448bc9cb8f4514dadda4aeede5f4/contracts/UniswapV2Router02.sol
interface ExtendedUni2Router is UniswapV2Router02Like {
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

// https://github.com/Uniswap/v2-core/blob/ee547b17853e71ed4e0101ccfd52e70d5acded58/contracts/UniswapV2Factory.sol
interface UniswapV2FactoryLike {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

}

// https://github.com/Uniswap/v2-core/blob/ee547b17853e71ed4e0101ccfd52e70d5acded58/contracts/UniswapV2Pair.sol
interface UniswapV2PairLike {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract User {}

contract KilnTest is Test {

    using UniswapV2Library for *;

    Recipe2 kiln;
    QuoterTwap qtwap;
    Univ3Quoter univ3Quoter;
    User user;

    uint256 halfLot;
    uint256 refOneWad;
    uint256 refHalfLot;

    address pairToken;
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
        univ3Quoter = Univ3Quoter(UNIV3QUOTER);
        pairToken = UniswapV2Library.pairFor(ExtendedUni2Router(UNIV2ROUTER).factory(), DAI, MKR);

        kiln.file("lot", 15_000 * WAD);
        kiln.file("hop", 6 hours);
        kiln.file("path", path);
        halfLot = kiln.lot() / 2;

        qtwap = new QuoterTwap(UNIV3FACTORY);
        qtwap.file("path", path);
        kiln.addQuoter(address(qtwap));

        // When changing univ3 price we'll have to relate to half lot amount, as that's what fire() trades there
        refHalfLot = getRefOutAMount(halfLot);
        // console.log("refHalfLot: %s", refHalfLot);

        // When changing univ2 price we'll use one WAD as reference fire only deposit theres (no price change)
        refOneWad = getRefOutAMount(WAD);

        // Bootstrapping -
        // As there's almost no initial liquidity in v2, need to arb the price then deposit a reasonable amount
        // As these are small amounts involved the assumption is that it will happen separately from kiln
        changeUniv2Price(WAD, refOneWad * 995 / 1000, refOneWad * 1005 / 1000);
    }

    function getRefOutAMount(uint256 amountIn) internal view returns (uint256) {
        return qtwap.quote(address(0), address(0), amountIn);
    }

    function changeUniv3Price(uint256 amountIn, uint256 minOutAmount, uint256 maxOutAMount) internal {
        uint256 current = univ3Quoter.quoteExactInput(path, amountIn);
        // console.log("univ3 minOutAmount: %s, current: %s, maxOutAmount: %s", minOutAmount, current, maxOutAMount);

        while (current < minOutAmount) {

            uint256 mkrAmount = 20 * WAD;
            deal(MKR, address(this), mkrAmount);
            GemLike(MKR).approve(UNIV3ROUTER, mkrAmount);
            SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
                path:             abi.encodePacked(MKR, uint24(3000), WETH, uint24(500), USDC, uint24(100), DAI),
                recipient:        address(this),
                deadline:         block.timestamp,
                amountIn:         mkrAmount,
                amountOutMinimum: 0
            });
            SwapRouterLike(UNIV3ROUTER).exactInput(params);

            current = univ3Quoter.quoteExactInput(path, amountIn);
            // console.log("univ3 driving out amount up - minOutAmount: %s, current: %s, maxOutAmount: %s", minOutAmount, current, maxOutAMount);
        }
        while (current > maxOutAMount) {

            // trade dai to mkr
            uint256 daiAmount = 20_000 * WAD;
            deal(DAI, address(this), daiAmount);
            GemLike(DAI).approve(UNIV3ROUTER, daiAmount);
            SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
                path:             abi.encodePacked(DAI, uint24(100), USDC, uint24(500), WETH, uint24(3000), MKR),
                recipient:        address(this),
                deadline:         block.timestamp,
                amountIn:         daiAmount,
                amountOutMinimum: 0
            });
            SwapRouterLike(UNIV3ROUTER).exactInput(params);

            current = univ3Quoter.quoteExactInput(path, amountIn);
            // console.log("univ3 driving out amount down - minOutAmount: %s, current: %s, maxOutAmount: %s", minOutAmount, current, maxOutAMount);
        }

        assert(current >= minOutAmount && current <= maxOutAMount);
    }

    function getUniv2AmountOut(uint256 amountIn) internal returns (uint256 amountOut) {
        uint reserveA;
        uint reserveB;

        (address token0,) = UniswapV2Library.sortTokens(DAI, MKR);
        (uint reserve0, uint reserve1,) = UniswapV2PairLike(pairToken).getReserves();
        (reserveA, reserveB) = DAI == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        amountOut = ExtendedUni2Router(UNIV2ROUTER).getAmountOut(amountIn, reserveA, reserveB);
    }

    function changeUniv2Price(uint256 amountIn, uint256 minOutAmount, uint256 maxOutAMount) internal {
        uint256 current = getUniv2AmountOut(amountIn);
         // console.log("univ2 minOutAmount: %s, current: %s, maxOutAmount: %s", minOutAmount, current, maxOutAMount);

        while (current < minOutAmount) {

            address[] memory _path = new address[](2);
            _path[0] = MKR;
            _path[1] = DAI;

            uint256 mkrAmount = WAD / 10000;
            deal(MKR, address(this), mkrAmount);
            GemLike(MKR).approve(UNIV2ROUTER, mkrAmount);
            ExtendedUni2Router(UNIV2ROUTER).swapExactTokensForTokens(
                mkrAmount,         // amountIn
                0,                 // amountOutMin
                _path,             // path
                address(this),     // to
                block.timestamp
            );  // deadline

            current = getUniv2AmountOut(amountIn);
            // console.log("univ2 driving out amount up - minOutAmount: %s, current: %s, maxOutAmount: %s", minOutAmount, current, maxOutAMount);
        }
        while (current > maxOutAMount) {

            // trade dai to mkr
            address[] memory _path = new address[](2);
            _path[0] = DAI;
            _path[1] = MKR;

            uint256 daiAmount = 1 * WAD / 10;
            deal(DAI, address(this), daiAmount);
            GemLike(DAI).approve(UNIV2ROUTER, daiAmount);
            ExtendedUni2Router(UNIV2ROUTER).swapExactTokensForTokens(
                daiAmount,          // amountIn
                0,                 // amountOutMin
                _path,             // path
                address(this),     // to
                block.timestamp
            );  // deadline

            current = getUniv2AmountOut(amountIn);
            // console.log("univ2 driving out amount down - minOutAmount: %s, current: %s, maxOutAmount: %s", minOutAmount, current, maxOutAMount);
        }

        assert(current >= minOutAmount && current <= maxOutAMount);
    }

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

    function testFileZen() public {
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("zen"), 7);
        kiln.file("zen", 7);
        assertEq(kiln.zen(), 7);
    }

    function testFileYenZero() public {
        vm.expectRevert("Recipe2/zero-yen");
        kiln.file("yen", 0);
    }

    function testFileZenZero() public {
        vm.expectRevert("Recipe2/zero-zen");
        kiln.file("zen", 0);
    }

    // TODO: move to new quoter
    /*
    function testFileScope() public {
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("scope"), 314);
        kiln.file("scope", 314);
        assertEq(kiln.scope(), 314);
    }

    function testFileZeroScope() public {
        vm.expectRevert("Recipe2/zero-scope");
        kiln.file("scope", 0);
    }


    function testFileScopeTooLarge() public {
        vm.expectRevert("Recipe2/scope-overflow");
        kiln.file("scope", uint32(type(int32).max) + 1);
    }
    */

    function testFileBytesUnrecognized() public {
        vm.expectRevert("Recipe2/file-unrecognized-param");
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

    function testFileZenNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.file("zen", 7);
    }

    function testFileScopeNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.file("scope", 413);
    }

    /*
    Given a reference TWAP out amount, we want to test the following scenarios.
    Note that `Higher` stands for higher out amount than the reference, while `Lower` stands for lower out amount
    than the reference.

    When Univ3 out amount is higher than the reference a yen of 100% should allow it, and we assume 105% blocks it.
    When Univ3 out amount is lower than the reference we assume a yen of 95% should allow it, and 100% blocks it.
    When Univ2 out amount is either lower or higher a zen of 95% should allow it, and 100% blocks it.

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

    function testFireUniv3HigherYenAllowsUniv2HigherZenAllows() public {
        changeUniv3Price(halfLot, refHalfLot, refHalfLot * 102 / 100);
        kiln.file("yen", 100 * WAD / 100);

        changeUniv2Price(WAD, refOneWad, refOneWad * 102 / 100);
        kiln.file("zen", 98 * WAD / 100);

        deal(DAI, address(kiln), 50_000 * WAD);
        kiln.fire();

        assertGt(GemLike(UNIV2DAIMKRLP).balanceOf(address(user)), 0);
        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(kiln)), 0);
    }

    function testFireUniv3HigherYenAllowsUniv2HigherZenBlocks() public {
        changeUniv3Price(halfLot, refHalfLot, refHalfLot * 102 / 100);
        kiln.file("yen", 100 * WAD / 100);

        changeUniv2Price(WAD, refOneWad, refOneWad * 102 / 100);
        kiln.file("zen", 1 * WAD);

        deal(DAI, address(kiln), 50_000 * WAD);

        // Note that if both uniV2 min amounts don't suffice the revert is "INSUFFICIENT_A_AMOUNT" -
        // https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol#L56
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        kiln.fire();
    }

    function testFireUniv3HigherYenAllowsUniv2LowerZenAllows() public {
        changeUniv3Price(halfLot, refHalfLot, refHalfLot * 102 / 100);
        kiln.file("yen", 100 * WAD / 100);

        changeUniv2Price(WAD, refOneWad * 98 / 100, refOneWad);
        kiln.file("zen", 98 * WAD / 100);

        deal(DAI, address(kiln), 50_000 * WAD);
        kiln.fire();

        assertGt(GemLike(UNIV2DAIMKRLP).balanceOf(address(user)), 0);
        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(kiln)), 0);
    }

    function testFireUniv3HigherYenAllowsUniv2LowerZenBlocks() public {
        changeUniv3Price(halfLot, refHalfLot, refHalfLot * 102 / 100);
        kiln.file("yen", 100 * WAD / 100);

        changeUniv2Price(WAD, refOneWad * 98 / 100, refOneWad);
        kiln.file("zen", 1 * WAD);

        deal(DAI, address(kiln), 50_000 * WAD);
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        kiln.fire();
    }

    function testFireUniv3HigherYenBlocks() public {
        changeUniv3Price(halfLot, refHalfLot, refHalfLot * 102 / 100);
        kiln.file("yen", 102 * WAD / 100);

        deal(DAI, address(kiln), 50_000 * WAD);
        vm.expectRevert("Too little received");
        kiln.fire();
    }

    // this
    function testFireUniv3LowerYenAllowsUniv2HigherZenAllows() public {
        changeUniv3Price(halfLot, refHalfLot * 98 / 100, refHalfLot);
        kiln.file("yen", 98 * WAD / 100);

        changeUniv2Price(WAD, refOneWad, refOneWad * 102 / 100);
        kiln.file("zen", 98 * WAD / 100);

        deal(DAI, address(kiln), 50_000 * WAD);
        kiln.fire();

        assertGt(GemLike(UNIV2DAIMKRLP).balanceOf(address(user)), 0);
        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(kiln)), 0);
    }


    function testFireUniv3LowerYenAllowsUniv2HigherZenBlocks() public {
        changeUniv3Price(halfLot, refHalfLot * 98 / 100, refHalfLot);
        kiln.file("yen", 98 * WAD / 100);

        changeUniv2Price(WAD, refOneWad, refOneWad * 102 / 100);
        kiln.file("zen", 1 * WAD);

        deal(DAI, address(kiln), 50_000 * WAD);
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        kiln.fire();
    }

    function testFireUniv3LowerYenAllowsUniv2LowerZenAllows() public {
        changeUniv3Price(halfLot, refHalfLot * 98 / 100, refHalfLot);
        kiln.file("yen", 98 * WAD / 100);

        changeUniv2Price(WAD, refOneWad * 98 / 100, refOneWad);
        kiln.file("zen", 98 * WAD / 100);

        deal(DAI, address(kiln), 50_000 * WAD);
        kiln.fire();

        assertGt(GemLike(UNIV2DAIMKRLP).balanceOf(address(user)), 0);
        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(kiln)), 0);
    }

    function testFireUniv3LowerYenAllowsUniv2LowerZenBlocks() public {
        changeUniv3Price(halfLot, refHalfLot * 98 / 100, refHalfLot);
        kiln.file("yen", 98 * WAD / 100);

        changeUniv2Price(WAD, refOneWad * 98 / 100, refOneWad);
        kiln.file("zen", 1 * WAD);

        deal(DAI, address(kiln), 50_000 * WAD);
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        kiln.fire();
    }

    function testFireUniv3LowerYenBlocks() public {
        changeUniv3Price(halfLot, refHalfLot * 98 / 100, refHalfLot);
        kiln.file("yen", 1 * WAD);

        deal(DAI, address(kiln), 50_000 * WAD);
        vm.expectRevert("Too little received");
        kiln.fire();
    }
}
