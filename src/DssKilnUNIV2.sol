// SPDX-License-Identifier: GPL-3.0-or-later
//
// DssKilnUNIV2 - Burn Module for Uniswap V2
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

pragma solidity ^0.6.12;

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

contract DssKilnUNIV2 is DssKiln {

    address public immutable uniV2Router;

    constructor(address _uniV2Router) public DssKiln() {
        uniV2Router = _uniV2Router;
    }

    function _swap(uint256 _amount) internal override returns (uint256 _swapped) {
        require(GemLike(DAI).approve(uniV2Router, _amount));

        address[] memory _path = new address[](2);
        _path[0] = DAI;
        _path[1] = MKR;
        uint256[] memory _amounts = UniswapRouterV2Like(uniV2Router).swapExactTokensForTokens(
            _amount,           // amountIn
            0,                 // amountOutMin
            _path,             // path
            address(this),     // to
            block.timestamp);  // deadline
        _swapped = _amounts[_amounts.length - 1];
        require(GemLike(MKR).balanceOf(address(this)) >= _swapped, "DssKilnUNIV2/swapped-balance-not-available");
    }
}
