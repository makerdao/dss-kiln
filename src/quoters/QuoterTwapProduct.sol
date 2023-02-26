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

import {IQuoter}     from "src/quoters/IQuoter.sol";
import {FullMath}    from "src/uniV3/FullMath.sol";
import {TickMath}    from "src/uniV3/TickMath.sol";
import {PoolAddress} from "src/uniV3/PoolAddress.sol";
import {Path}        from "src/uniV3/Path.sol";

// https://github.com/Uniswap/v3-core/blob/412d9b236a1e75a98568d49b1aeb21e3a1430544/contracts/UniswapV3Pool.sol
interface UniswapV3PoolLike {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function observe(uint32[] calldata) external view returns (int56[] memory, uint160[] memory);
}

contract QuoterTwapProduct is IQuoter {
    using Path for bytes;

    mapping (address => uint256) public wards;
    uint256 public scope; // [Seconds]  Time period for TWAP calculations
    bytes   public path;  //            ABI-encoded UniV3 compatible path

    address public immutable uniFactory;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, bytes data);

    constructor(address _uniFactory) {
        uniFactory = _uniFactory;

        scope = 1 hours;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "QuoterTwapProduct/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    /**
        @dev Auth'ed function to update scope
             Warning - a low `scope` increases the susceptibility to oracle manipulation attacks
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, uint256 data) external auth {
        if (what == "scope") {
            require(data > 0, "QuoterTwapProduct/zero-scope");
            require(data <= uint32(type(int32).max), "QuoterTwapProduct/scope-overflow");
            scope = data;
        } else revert("QuoterTwapProduct/file-unrecognized-param");
        emit File(what, data);
    }

    /**
        @dev Auth'ed function to update path value
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, bytes calldata data) external auth {
        if (what == "path") path = data;
        else revert("QuoterTwapProduct/file-unrecognized-param");
        emit File(what, data);
    }

    // https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/lens/Quoter.sol#L106
    function quote(address, address, uint256 amountIn) external view returns (uint256 amountOut) {
        bytes memory _path = path;
        while (true) {
            bool hasMultiplePools = _path.hasMultiplePools();

            (address tokenIn, address tokenOut, uint24 fee) = _path.decodeFirstPool();
            int24 arithmeticMeanTick = _consult(_getPool(tokenIn, tokenOut, fee), uint32(scope));

            require(amountIn <= type(uint128).max, "QuoterTwapProduct/amountIn-overflow");
            amountIn = _getQuoteAtTick(arithmeticMeanTick, uint128(amountIn), tokenIn, tokenOut);

            // Decide whether to continue or terminate
            if (hasMultiplePools) {
                _path = _path.skipToken();
            } else {
                return amountIn;
            }
        }
    }

    // https://github.com/Uniswap/v3-periphery/blob/51f8871aaef2263c8e8bbf4f3410880b6162cdea/contracts/lens/Quoter.sol#L29
    function _getPool(address tokenA, address tokenB, uint24 fee) internal view returns (UniswapV3PoolLike) {
        return UniswapV3PoolLike(PoolAddress.computeAddress(uniFactory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    // https://github.com/Uniswap/v3-periphery/blob/51f8871aaef2263c8e8bbf4f3410880b6162cdea/contracts/libraries/OracleLibrary.sol#L16
    function _consult(UniswapV3PoolLike pool, uint32 _scope) internal view returns (int24 arithmeticMeanTick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = _scope;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        arithmeticMeanTick = int24(tickCumulativesDelta / int56(int32(_scope)));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(int32(_scope)) != 0)) arithmeticMeanTick--;
    }

    // https://github.com/Uniswap/v3-periphery/blob/51f8871aaef2263c8e8bbf4f3410880b6162cdea/contracts/libraries/OracleLibrary.sol#L49
    function _getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
            ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
            : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
            ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
            : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
