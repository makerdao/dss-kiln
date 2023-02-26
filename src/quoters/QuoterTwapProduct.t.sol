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
import "src/quoters/QuoterTwapProduct.sol";

// https://github.com/Uniswap/v3-periphery/blob/v1.0.0/contracts/lens/Univ3Quoter.sol#L106-L122
interface Univ3Quoter {
    function quoteExactInput(
        bytes calldata path,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}

contract QuoterTwapProductTest is Test {
    QuoterTwapProduct tpQuoter;
    Univ3Quoter quoter;

    uint256 amtIn;
    uint32 scope;
    bytes path;

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MKR  = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    address constant QUOTER      = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant UNIFACTORY  = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint256 constant WAD = 1e18;

    function assertEqApproxBPS(uint256 _a, uint256 _b, uint256 _tolerance_bps) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _b * _tolerance_bps / 10 ** 4) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function setUp() public {
        quoter = Univ3Quoter(QUOTER);
        tpQuoter = new QuoterTwapProduct(UNIFACTORY);

        // default testing values
        path = abi.encodePacked(DAI, uint24(100), USDC, uint24(500), WETH, uint24(3000), MKR);
        amtIn = 30_000 * WAD;
        scope = 0.5 hours;

        tpQuoter.file("path", path);
        tpQuoter.file("scope", scope);
    }

    function testSingleHopPath() public {
        bytes memory _path = abi.encodePacked(USDC, uint24(500), WETH);
        tpQuoter.file("path", _path);
        amtIn = 30_000 * 1e6;

        uint256 quoterAmt = quoter.quoteExactInput(_path, amtIn);
        uint256 tpQuoterAmt = tpQuoter.quote(address(0), address(0), amtIn);

        assertEqApproxBPS(tpQuoterAmt, quoterAmt, 500);
    }

    function testMultiHopPath() public {
        uint256 quoterAmt = quoter.quoteExactInput(path, amtIn);
        uint256 tpQuoterAmt = tpQuoter.quote(address(0), address(0), amtIn);

        assertEqApproxBPS(tpQuoterAmt, quoterAmt, 500);
    }

    function testInvalidPathSingleToken() public {
        tpQuoter.file("path", abi.encodePacked(USDC));

        vm.expectRevert("toUint24_outOfBounds");
        tpQuoter.quote(address(0), address(0), amtIn);
    }

    function testInvalidPathSameToken() public {
        tpQuoter.file("path", abi.encodePacked(USDC, uint24(500), USDC));

        vm.expectRevert();
        tpQuoter.quote(address(0), address(0), amtIn);
    }

    function testInvalidPathTwoFees() public {
        tpQuoter.file("path", abi.encodePacked(USDC, uint24(500), uint24(500), USDC));

        vm.expectRevert();
        tpQuoter.quote(address(0), address(0), amtIn);
    }

    function testInvalidPathWrongFees() public {
        tpQuoter.file("path", abi.encodePacked(USDC, uint24(501), USDC));

        vm.expectRevert();
        tpQuoter.quote(address(0), address(0), amtIn);
    }

    function testZeroAmt() public {
        amtIn = 0;

        uint256 tpQuoterAmt = tpQuoter.quote(address(0), address(0), amtIn);
        assertEq(tpQuoterAmt, 0);
    }

    function testTooLargeAmt() public {
        amtIn = uint256(type(uint128).max) + 1;

        vm.expectRevert("QuoterTwapProduct/amountIn-overflow");
        tpQuoter.quote(address(0), address(0), amtIn);
    }

    // TWAP returns the counterfactual accumulator values at exactly the timestamp between two observations.
    // This means that a small scope should lean very close to the current price.
    function testSmallScope() public {
        tpQuoter.file("scope", 1 seconds);

        uint256 quoterAmt = quoter.quoteExactInput(path, amtIn);
        uint256 tpQuoterAmt = tpQuoter.quote(address(0), address(0), amtIn);
        assertEqApproxBPS(tpQuoterAmt, quoterAmt, 500); // Note that there is still price impact for amtIn
    }

    function testSmallScopeSmallAmt() public {
        amtIn = 1 * WAD / 100;
        tpQuoter.file("scope", 1 seconds);

        uint256 quoterAmt = quoter.quoteExactInput(path, amtIn);
        uint256 tpQuoterAmt = tpQuoter.quote(address(0), address(0), amtIn);
        assertEqApproxBPS(tpQuoterAmt, quoterAmt, 100); // Price impact for amtIn should be minimized
    }

    // using testFail as division by zero is not supported for vm.expectRevert
    function testFailZeroScope() public {
        tpQuoter.file("scope", 0 seconds);
        tpQuoter.quote(address(0), address(0), amtIn);
    }

    function testTooLargeScope() public {
        tpQuoter.file("scope", 100000 seconds);

        // https://github.com/Uniswap/v3-core/blob/fc2107bd5709cdee6742d5164c1eb998566bcb75/contracts/libraries/Oracle.sol#L226
        vm.expectRevert(bytes("OLD"));
        tpQuoter.quote(address(0), address(0), amtIn);
    }

    // Can be used for accumulating statistics through a wrapping script
    function testStat() public {
        amtIn = 30_000 * WAD;
        tpQuoter.file("scope", 30 minutes);

        uint256 quoterAmt = quoter.quoteExactInput(path, amtIn);
        uint256 tpQuoterAmt = tpQuoter.quote(address(0), address(0), amtIn);
        uint256 ratio = quoterAmt * WAD / tpQuoterAmt;

        console.log('{"tag": "Debug", "block": %s, "timestamp": %s, "ratio": %s}', block.number, block.timestamp, ratio);
    }
}
