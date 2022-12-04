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

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRouter.sol
interface SwapRouterLike {
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);
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

// https://github.com/makerdao/sai/blob/8b7a7359f40231131218b594fa59ac2bcee5f6ef/src/weth9.sol
interface WethLike {
    function withdraw(uint256) external;
}

// https://github.com/curvefi/curve-contract/blob/b0bbf77f8f93c9c5f4e415bce9cd71f0cdee960e/contracts/pools/steth/StableSwapSTETH.vy
interface CurvePoolLike {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
}

interface QuoterLike {
    function quote(address, address, uint256) external view returns (uint256);
}

contract KilnUniV3EthCurve is KilnBase {
    address[] public quoters; // TODO: add to kiln base
    bytes     public uniPath;

    address public immutable weth;
    address public immutable uniV3Router;
    address public immutable curvePool;
    int128  public immutable curveSendId;
    int128  public immutable curveReceiveId;
    address public immutable receiver;

    event File(bytes32 indexed what, bytes data);
    event AddQuoter(address indexed quoter);
    event RemoveQuoter(address indexed quoter, uint256 index);

    // @notice initialize a contract for buying eth through Uniswap V3, then swapping it through a Curve pool
    // @dev the minimal acceptable output amount is queried from a configured list of qouter contracts
    // @param _sell           the contract address of the token that will be sold
    // @param _buy            the contract address of the token that will be purchased
    // @param _weth           the contract address of the weth token
    // @param _uniV3Router    the address of the current Uniswap V3 swap router
    // @param _curvePool      the address of the curve pool to swap eth through
    // @param _curveSendId    the curve pool token id for the sent token (eth)
    // @param _curveReceiveId the curve pool token id for the received token
    // @param _receiver       the address of the account which will receive the funds to be bought
    constructor(
        address _sell,
        address _buy,
        address _weth,
        address _uniV3Router,
        address _curvePool,
        int128 _curveSendId,
        int128 _curveReceiveId,
        address _receiver
    )
        KilnBase(_sell, _buy)
    {
        weth           = _weth;
        uniV3Router    = _uniV3Router;
        curvePool      = _curvePool;
        curveSendId    = _curveSendId;
        curveReceiveId = _curveReceiveId;
        receiver       = _receiver;
    }

    function _max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }

    /**
        @dev Auth'ed function to update path value
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, bytes calldata data) external auth {
        if (what == "uniPath") uniPath = data;
        else revert("KilnUniV3EthCurve/file-unrecognized-param");
        emit File(what, data);
    }

    /**
        @dev Auth'ed function to add a quoter contract
        @param quoter   Quoter contract to add
    */
    function addQuoter(address quoter) external auth {
        quoters.push(quoter);
        emit AddQuoter(quoter);
    }

    /**
        @dev Auth'ed function to remove a quoter contract
        @param index   Index of quoter contract to remove
    */
    function removeQuoter(uint256 index) external auth {
        address quoter = quoters[index];
        quoters[index] = quoters[quoters.length - 1];
        quoters.pop();
        emit RemoveQuoter(quoter, index);
    }

    function _swap(uint256 amount) internal override returns (uint256 swapped) {
        uint256 amountMin;
        for (uint256 i = 0; i < quoters.length; i++) {
            amountMin = _max(amountMin, QuoterLike(quoters[i]).quote(sell, buy, amount));
        }

        GemLike(sell).approve(uniV3Router, amount);
        ExactInputParams memory params = ExactInputParams({
            path:             uniPath,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         amount,
            amountOutMinimum: 0
        });
        uint256 uniOut = SwapRouterLike(uniV3Router).exactInput(params);

        WethLike(weth).withdraw(uniOut);
        swapped = CurvePoolLike(curvePool).exchange{value: uniOut}({
            i:      curveSendId,
            j:      curveReceiveId,
            dx:     uniOut,
            min_dy: amountMin
        });
        GemLike(buy).transfer(receiver, swapped);
    }

    function _drop(uint256) internal override {}

    receive() external payable {}
}
