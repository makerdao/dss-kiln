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

interface TestGem {
    function totalSupply() external view returns (uint256);
}

// https://github.com/Uniswap/v3-periphery/blob/v1.0.0/contracts/lens/UNIV3Quoter.sol#L106-L122
interface UNIV3Quoter {
    function quoteExactInput(
        bytes calldata path,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}

contract User {}

contract KilnTest is Test {
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
    }


    function mintDai(address usr, uint256 amt) internal {
        deal(DAI, usr, amt);
        assertEq(GemLike(DAI).balanceOf(address(usr)), amt);
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

    function testFire() public { // TODO: can remove once we have the other tests
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(GemLike(UNIV2DAIMKRLP).balanceOf(address(user)), 0);
        assertEq(GemLike(DAI).balanceOf(address(kiln)),50_000 * WAD);

        kiln.fire();

        assertGt(GemLike(UNIV2DAIMKRLP).balanceOf(address(user)), 0);
        assertTrue(GemLike(DAI).balanceOf(address(kiln)) < 50_000 * WAD);
        assertEq(GemLike(MKR).balanceOf(address(kiln)), 0);
    }

    function testFireYenMuchLessThanTwap() public {}
    function testFireYenMuchMoreThanTwap() public {}
    function testFireYenZero() public {}

    function testFireAfterLowTwap() public {}
    function testFireAfterHighTwap() public {}

    function testFireMkrUpLessThanZen() public {}
    function testFireMkrUpMoreThanZen() public {}
    function testFireMkrDownLessThanZen() public {}
    function testFireMkrDownMoreThanZen() public {}

    function testFireZenWad() public {}
    function testFireZenZero() public {}

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
