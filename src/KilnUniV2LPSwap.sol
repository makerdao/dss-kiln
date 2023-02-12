// SPDX-License-Identifier: GPL-3.0-or-later
//
// DssKilnUNIV2Swap - Burn Module for Uniswap V2
//
// Copyright (C) 2023 Dai Foundation
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

import {KilnBase, GemLike} from "./KilnBase.sol";
import {UniswapV2Library} from "./uniV2/UniswapV2Library.sol";

// Resources:
//    https://docs.uniswap.org/contracts/v2/reference/smart-contracts/library
//    https://docs.uniswap.org/contracts/v2/reference/smart-contracts/router-02

interface UniswapRouterV2Like {
    function factory() external returns (address);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
}

contract KilnUniV2LPSwap is KilnBase {

    using UniswapV2Library for *;

    address public immutable uniV2Router;
    address public immutable pairToken;
    address public immutable receiver;

    event LogI(uint256);

    constructor(address _sell, address _buy, address _uniV2Router, address _receiver) KilnBase(_sell, _buy) {
        receiver = _receiver;
        uniV2Router = _uniV2Router;
        pairToken = UniswapRouterV2Like(_uniV2Router).factory().pairFor(_sell, _buy);
    }

    function _swap(uint256 _amount) internal override returns (uint256 _swapped) {

        uint256 _halfLot = _amount / 2;

        GemLike(sell).approve(uniV2Router, _amount);

        address[] memory _path = new address[](2);
        _path[0] = sell;
        _path[1] = buy;


        // Step 1: Swap half of sell token for buy token.
        uint256[] memory _amounts = UniswapRouterV2Like(uniV2Router).swapExactTokensForTokens(
            _halfLot,          // amountIn
            0,                 // amountOutMin  // TODO: consider slippage protection here
            _path,             // path
            address(this),     // to
            block.timestamp);  // deadline
        _swapped = _amounts[_amounts.length - 1];

        // Step 2: Add liquidity
        GemLike(buy).approve(uniV2Router, _swapped);
        (,, uint256 _liquidity) = UniswapRouterV2Like(uniV2Router).addLiquidity(
            sell,              // tokenA
            buy,               // tokenB
            _halfLot,          // amountADesired
            _swapped,          // amountBDesired
            1,                 // amountAMin
            _swapped,          // amountBMin // irrelevant - can be very large
            receiver,          // to
            block.timestamp);  // deadline
        _swapped = _liquidity;

        // TODO TESTING: remove buy balance require and add test to prevent 3rd party lock if sending buy token
        // TODO add functionality for adding liquidity when buy token is sent to contract
        require(GemLike(buy).balanceOf(address(this)) == 0);
        require(GemLike(pairToken).balanceOf(receiver) >= _swapped, "KilnUniV2LPSwap/swapped-balance-not-available");
    }

    function _drop(uint256 _amount) internal override {}
}
