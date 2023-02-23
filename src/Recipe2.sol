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

import {KilnBase, GemLike} from "./KilnBase.sol";
import {TwapProduct}       from "./uniV3/TwapProduct.sol";

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRouter.sol
interface SwapRouterLike {
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);
    function factory() external returns (address factory);

    // https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/interfaces/ISwapRouter.sol#L26
    // https://docs.uniswap.org/protocol/guides/swaps/multihop-swaps#input-parameters
    struct ExactInputParams {
        bytes   path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
}

// https://github.com/Uniswap/v2-periphery/blob/dda62473e2da448bc9cb8f4514dadda4aeede5f4/contracts/UniswapV2Router02.sol
interface UniswapV2Router02Like {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

contract Recipe2 is KilnBase, TwapProduct {
    uint256 public scope; // [Seconds]  Time period for TWAP calculations
    uint256 public yen;   // [WAD]      Relative multiplier of the Univ3 TWAP price to insist on in the UniV3 trade
                          //            For example: 0.98 * WAD allows 2% worse price than the V3 TWAP
    uint256 public zen;   // [WAD]      Allowed Univ2 deposit price deviations from the Univ3 TWAP price. Must be <= WAD
                          //            For example: 0.97 * WAD allows 3% price deviation to either side.
    bytes   public path;  //            ABI-encoded UniV3 compatible path

    address public immutable uniV2Router;
    address public immutable uniV3Router;
    address public immutable receiver;

    event File(bytes32 indexed what, bytes data);

    // @notice initialize a Uniswap V3 routing path contract
    // @dev In order to complete fire() has to trade on UniV3 and deposit to UniV2. With the initial constructor value of
    //      `yen` == WAD, fire will trade on Univ3 only when the amount of tokens received is equal or better than the Univ3
    //      1 hour average price (`reference price`).
    //      For the Univ2 deposit to work `zen` has to be reduced from the default value of WAD by the allowed
    //      divergence from the reference price.
    //
    // @param _sell          the contract address of the token that will be sold
    // @param _buy           the contract address of the token that will be purchased
    // @param _uniV2Router   the address of the current Uniswap V2 swap router
    // @param _uniV3Router   the address of the current Uniswap V3 swap router
    // @param _receiver      the address of the account which will receive the funds to be bought
    constructor(
        address _sell,
        address _buy,
        address _uniV2Router,
        address _uniV3Router,
        address _receiver
    )
        KilnBase(_sell, _buy)
        TwapProduct(SwapRouterLike(_uniV3Router).factory())
    {
        uniV2Router = _uniV2Router;
        uniV3Router = _uniV3Router;
        receiver    = _receiver;

        scope = 1 hours;
        yen = WAD;
        zen = WAD;
    }

    uint256 constant WAD = 10 ** 18;

    /**
        @dev Auth'ed function to update path value
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, bytes calldata data) external auth {
        if (what == "path") path = data;
        else revert("Recipe2/file-unrecognized-param");
        emit File(what, data);
    }

    /**
        @dev Auth'ed function to update yen, scope, or base contract derived values
             Warning - setting `yen` or `zen` as a low value highly increases the susceptibility to oracle manipulation attacks
             Warning - a low `scope` increases the susceptibility to oracle manipulation attacks
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, uint256 data) public override auth {
        if (what == "yen") {
            require(data > 0, "Recipe2/zero-yen");
            yen = data;
        }  else if (what == "zen")  {
            require(data > 0, "Recipe2/zero-zen");
            zen = data;
        }  else if (what == "scope") {
            require(data > 0, "Recipe2/zero-scope");
            require(data <= uint32(type(int32).max), "Recipe2/scope-overflow");
            scope = data;
        } else {
            super.file(what, data);
            return;
        }
        emit File(what, data);
    }

    function _swap(uint256 inAmount) internal override returns (uint256 swapped) {

        uint256 _halfIn = inAmount / 2;
        bytes memory _path = path;
        uint256 _quote = quote(_path, _halfIn, uint32(scope));

        GemLike(sell).approve(uniV3Router, _halfIn);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             _path,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         _halfIn,
            amountOutMinimum: _quote * yen / WAD
        });
        uint256 bought = SwapRouterLike(uniV3Router).exactInput(params);

        // In case the `sell` token deposit amount needs to be insisted on it means the full `bought` amount of buy tokens are deposited.
        // Therefore we want at least the reference price (halfIn / quote) factored by zen.
        uint256 _zen = zen;
        uint256 sellDepositMin = (bought * _halfIn / _quote) * _zen / WAD;

        // In case the `buy` token deposit amount needs to be insisted on it means the full `halfIn` amount of sell tokens are deposited.
        // As `halflot` was also used in the quote calculation, it represents the exact reference price and only needs to be factored by zen
        uint256 buyDepositMin  = _quote * _zen / WAD;

        GemLike(sell).approve(uniV2Router, _halfIn);
        GemLike(buy).approve(uniV2Router, bought);
        (, uint256 amountB, uint256 liquidity) = UniswapV2Router02Like(uniV2Router).addLiquidity({
            tokenA:         sell,
            tokenB:         buy,
            amountADesired: _halfIn,
            amountBDesired: bought,
            amountAMin:     sellDepositMin,
            amountBMin:     buyDepositMin,
            to:             receiver,
            deadline:       block.timestamp
        });
        swapped = liquidity;

        // If not all buy tokens were used, send the remainder to the receiver
        if (bought > amountB) {
            GemLike(buy).transfer(receiver, bought - amountB);
        }
    }

    function _drop(uint256) internal override {}
}
