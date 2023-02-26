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

import {KilnBase, GemLike} from "./KilnBase.sol";
import {QuoterTwapProduct} from "./quoters/QuoterTwapProduct.sol";

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRouter.sol
interface SwapRouterLike {
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);
    function factory() external returns (address factory);
}

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/interfaces/ISwapRouter.sol#L26
// https://docs.uniswap.org/protocol/guides/swaps/multihop-swaps#input-parameters
struct ExactInputParams {
    bytes   path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
}

interface Quoter {
    function quote(address sell, address buy, uint256 amount) external returns (uint256 outAMount);
}

contract KilnUniV3 is KilnBase {
    uint256 public yen;   // [WAD]      Relative multiplier of the TWAP's price to insist on
    bytes   public path;  //            ABI-encoded UniV3 compatible path

    address[] public quoters;

    address public immutable uniV3Router;
    address public immutable receiver;

    event File(bytes32 indexed what, bytes data);

    // TODO: update documentation
    // @notice initialize a Uniswap V3 routing path contract
    // @dev TWAP-relative trading is enabled by default. With the initial values, fire will 
    //      perform the trade only when the amount of tokens received is equal or better than
    //      the 1 hour average price.
    // @param _sell          the contract address of the token that will be sold
    // @param _buy           the contract address of the token that will be purchased
    // @param _uniV3Router   the address of the current Uniswap V3 swap router
    // @param _receiver      the address of the account which will receive the funds to be bought
    constructor(
        address _sell,
        address _buy,
        address _uniV3Router,
        address _receiver
    )
        KilnBase(_sell, _buy)
    {
        uniV3Router = _uniV3Router;
        receiver    = _receiver;

        yen = WAD;
    }

    uint256 constant WAD = 10 ** 18;

    function _max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }

    /**
        @dev Auth'ed function to update path value
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, bytes calldata data) external auth {
        if (what == "path") path = data;
        else revert("KilnUniV3/file-unrecognized-param");
        emit File(what, data);
    }

    // TODO: update documentation
    /**
        @dev Auth'ed function to update yen, scope, or base contract derived values
             Warning - setting `yen` as 0 or another low value highly increases the susceptibility to oracle manipulation attacks
             Warning - a low `scope` increases the susceptibility to oracle manipulation attacks
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, uint256 data) public override auth {
        if (what == "yen") yen = data;
        else {
            super.file(what, data);
            return;
        }
        emit File(what, data);
    }

    // TODO: documentation
    function addQuoter(address quoter) external auth {
        quoters.push(quoter);
    }

    function removeQuoter(uint256 index) external auth {
        quoters[index] = quoters[quoters.length - 1];
        quoters.pop();
    }

    function quote(address sell, address buy, uint256 amount) public returns (uint256 outAMount) {
        for(uint256 i; i < quoters.length; i++) {
            outAMount = _max(outAMount, Quoter(quoters[i]).quote(sell, buy, amount));
        }
    }

    function _swap(uint256 amount) internal override returns (uint256 swapped) {
        GemLike(sell).approve(uniV3Router, amount);

        bytes   memory _path = path;
        uint256        _yen  = yen;

        uint256 amountMin = (_yen != 0) ? quote(sell, buy, amount) * _yen / WAD : 0;

        ExactInputParams memory params = ExactInputParams({
            path:             _path,
            recipient:        receiver,
            deadline:         block.timestamp,
            amountIn:         amount,
            amountOutMinimum: amountMin
        });

        return SwapRouterLike(uniV3Router).exactInput(params);
    }

    function _drop(uint256) internal override {}
}
