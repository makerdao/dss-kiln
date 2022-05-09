// SPDX-License-Identifier: GPL-3.0-or-later
//
// DssKilnUNIV2BurnStrategy - Burn Module for Uniswap V2
//
// Copyright (C) 2022 Dai Foundation
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

pragma solidity ^0.8.13;

import "./DssKiln.sol";

interface UniswapRouterV2Like {
    function swapExactTokensForTokens(
      uint amountIn,
      uint amountOutMin,
      address[] calldata path,
      address to,
      uint deadline
  ) external returns (uint[] memory amounts);
}

contract DssKilnUNIV2BurnStrategy is DssKiln {

    address public immutable uniV2Router;

    constructor(address _sell, address _buy, address _uniV2Router) DssKiln(_sell, _buy) {
        uniV2Router = _uniV2Router;
    }

    /// @notice this implementation is currently susceptible to slippage and MEV losses.
    ///         It is currently provided as an example of a basic integration and is not
    ///         intended for prodution purposes in it's current state.
    function _swap(uint256 _amount) internal override returns (uint256 _swapped) {
        require(GemLike(sell).approve(uniV2Router, _amount));

        address[] memory _path = new address[](2);
        _path[0] = sell;
        _path[1] = buy;
        uint256[] memory _amounts = UniswapRouterV2Like(uniV2Router).swapExactTokensForTokens(
            _amount,           // amountIn
            0,                 // amountOutMin
            _path,             // path
            address(this),     // to
            block.timestamp);  // deadline
        _swapped = _amounts[_amounts.length - 1];
        require(GemLike(buy).balanceOf(address(this)) >= _swapped, "DssKilnUNIV2/swapped-balance-not-available");
    }

    function _drop(uint256 _amount) internal override {
        GemLike(buy).burn(_amount);
    }
}
