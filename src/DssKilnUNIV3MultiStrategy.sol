// SPDX-License-Identifier: GPL-3.0-or-later
//
// DssKilnUNIV3SaveStrategy - Buy and save tokens via Uniswap V3
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

pragma solidity ^0.8.14;

import "./DssKiln.sol";

// https://docs.uniswap.org/protocol/reference/periphery/interfaces/ISwapRouter#exactinput
interface UniswapRouterV3Like {
    function exactInput(ExactInputParams calldata params) external
        returns (uint256 amountOut);
}

interface TokenLike {
    function decimals() external view returns (uint256);
}

// https://docs.uniswap.org/protocol/reference/periphery/interfaces/ISwapRouter#exactinputparams
struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
}

contract DssKilnUNIV3MultiStrategy is DssKiln {

    address public immutable uniV3Router;
    address public immutable receiver;
    uint256 public           price;         // Max acceptable price to buy (in sell)
    bytes   public           path;          // abi-encoded UniV3 compatible path

    event File(bytes32 indexed what, bytes data);

    // @notice initialize a Uniswap V3 routing path contract
    // @param _sell the contract address of the token that will be sold
    // @param _buy  the contract address of the token that will be purchased
    // @param _uniV3Router the address of the current Uniswap V3 swap router
    // @param _receiver the address of the account which will receive the funds to be bought
    // @param _poolFee the Uniswap fee pool to use for trades (0.3% == 3000, 0.05% == 500)
    // @param _path
    //     https://docs.uniswap.org/protocol/guides/swaps/multihop-swaps#input-parameters
    //     Multiple pool swaps are encoded through bytes called a `path`. A path is a sequence of token addresses and poolFees that define the pools used in the swaps.
    //     The format for pool encoding is (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut) where tokenIn/tokenOut parameter is the shared token across the pools.
    // @param _maxPrice the maximum to pay per buy token (in sell tokens)
    constructor(address _sell, address _buy, address _uniV3Router, address _receiver) DssKiln(_sell, _buy) {
        uniV3Router = _uniV3Router;
        receiver = _receiver;
    }

    function file(bytes32 what, bytes calldata data) external auth {
        if (what == "path") { path = data; }
        else revert("DssKiln/file-unrecognized-param");
        emit File(what, data);
    }

    function filePrice(uint256 data) external auth {
        price = data;
        emit File("price", data);
    }

    function _swap(uint256 _amount) internal override returns (uint256 _swapped) {
        require(GemLike(sell).approve(uniV3Router, _amount));

        // Calculate the minimum amount to return if price is set.
        uint256 amountMin;
        if (price != 0) {
            amountMin = ((_amount * 10**TokenLike(sell).decimals()) + (price / 2)) / price;
        }

        ExactInputParams memory params = ExactInputParams(
            path,
            address(this),        // recipient
            block.timestamp,      // deadline
            _amount,              // amountIn
            amountMin             // amountOutMinimum
        );

        _swapped = UniswapRouterV3Like(uniV3Router).exactInput(params);
        require(GemLike(buy).balanceOf(address(this)) >= _swapped, "DssKilnUNIV3/swapped-balance-not-available");
    }

    /**
        @dev Transfer the purchased token to the receiver
     */
    function _drop(uint256 _amount) internal override {
        GemLike(buy).transfer(receiver, _amount);
    }
}
