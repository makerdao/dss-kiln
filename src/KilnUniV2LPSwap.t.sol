// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
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
import "./KilnUniV2LPSwap.sol";

interface TestGem {
    function totalSupply() external view returns (uint256);
}

interface UniswapV2RouterExtendedLike is UniswapRouterV2Like {
    function quote(uint256, uint256 ,uint256) external pure returns (uint256);
    function getAmountOut(uint256, uint256, uint256) external pure returns (uint256);
}

interface UniswapV2FactoryLike {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
}

interface UniswapV2PairLike {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
}



contract User {}

contract KilnTest is Test {
    KilnUniV2LPSwap kiln;
    User user;

    using UniswapV2Library for *;


    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MKR  = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    uint256 constant WAD = 1e18;

    address constant ROUTER   = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    event File(bytes32 indexed what, bytes data);
    event File(bytes32 indexed what, uint256 data);

    function setUp() public {
        user = new User();

        kiln = new KilnUniV2LPSwap(DAI, MKR, ROUTER, address(user));

        kiln.file("lot", 50000 * WAD);
        kiln.file("hop", 6 hours);
    }

    function topUpLiquidity() internal {
        uint256 daiAmt = 5_000_000 * WAD;
        uint256 mkrAmt = 5000 * WAD;

        uint reserveA;
        uint reserveB;
        (address token0,) = UniswapV2Library.sortTokens(DAI, MKR);
        (uint reserve0, uint reserve1,) = UniswapV2PairLike(kiln.pairToken()).getReserves();
        (reserveA, reserveB) = DAI == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        mkrAmt = daiAmt / (reserveA / reserveB) - 10 * WAD;

        deal(DAI, address(this), daiAmt);
        deal(MKR, address(this), mkrAmt);

        GemLike(DAI).approve(ROUTER, daiAmt);
        GemLike(MKR).approve(ROUTER, mkrAmt);

        UniswapRouterV2Like(ROUTER).addLiquidity(
            MKR,
            DAI,
            mkrAmt,
            daiAmt,
            mkrAmt,
            1,
            address(this),
            block.timestamp);

        assertGt(GemLike(kiln.pairToken()).balanceOf(address(this)), 0);
    }

    function mintDai(address usr, uint256 amt) internal {
        deal(DAI, usr, amt);
        assertEq(GemLike(DAI).balanceOf(address(usr)), amt);
    }

    function mintMKR(address usr, uint256 amt) internal {
        deal(MKR, usr, amt);
        assertEq(GemLike(MKR).balanceOf(address(usr)), amt);
    }

    function testFireV2Single() public {
        mintDai(address(kiln), 100_000 * WAD);
        topUpLiquidity();

        assertEq(GemLike(kiln.pairToken()).balanceOf(address(user)), 0);

        kiln.file("lot", 20000 * WAD);

        kiln.fire();

        assertGt(GemLike(kiln.pairToken()).balanceOf(address(user)), 0);
    }

    function testFireV2Multi() public {
        mintDai(address(kiln), 100_000 * WAD);
        topUpLiquidity();

        assertEq(GemLike(kiln.pairToken()).balanceOf(address(user)), 0);

        kiln.file("lot", 20000 * WAD);

        kiln.fire();

        skip(6 hours);

        kiln.fire();

        assertGt(GemLike(kiln.pairToken()).balanceOf(address(user)), 0);
    }

    // TODO: test frontrun
    // TODO: test and account for 3rd party sending MKR to kiln
}
