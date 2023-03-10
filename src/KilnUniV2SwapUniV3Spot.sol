// SPDX-License-Identifier: GPL-3.0-or-later
//
// KilnUniV2SwapUniV3Spot - Price Controller for KilnUniV2Swap
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

import {KilnBase}          from "./KilnBase.sol";
import {TwapProduct}       from "./uniV3/TwapProduct.sol";

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRouter.sol
interface SwapRouterLike {
    function factory() external returns (address factory);
}

contract KilnUniV2SwapUniV3Spot is TwapProduct {

    address public immutable kiln;
    address public immutable uniV3Router;

    uint256 public yen;   // [WAD]      Relative multiplier of the TWAP's price to insist on
    uint256 public scope; // [Seconds]  Time period for TWAP calculations
    bytes   public path;  //            ABI-encoded UniV3 compatible path

    uint256 internal constant WAD = 10 ** 18;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, bytes data);

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "KilnUniV2SwapUniV3Spot/not-authorized");
        _;
    }

    constructor(address _kiln, address _uniV3Router) TwapProduct(SwapRouterLike(_uniV3Router).factory()) {
        kiln = _kiln;
        uniV3Router = _uniV3Router;

        scope = 1 hours;
        yen   = WAD;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /**
        @dev Auth'ed function to update path value
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, bytes calldata data) external auth {
        if (what == "path") path = data;
        else revert("KilnUniV2SwapUniV3Spot/file-unrecognized-param");
        emit File(what, data);
    }

    /**
        @dev Auth'ed function to update yen, scope, or base contract derived values
             Warning - setting `yen` as 0 or another low value highly increases the susceptibility to oracle manipulation attacks
             Warning - a low `scope` increases the susceptibility to oracle manipulation attacks
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, uint256 data) public auth {
        if      (what == "yen") yen = data;
        else if (what == "scope") {
            require(data > 0, "KilnUniV3/zero-scope");
            require(data <= uint32(type(int32).max), "KilnUniV3/scope-overflow");
            scope = data;
        } else {
            revert("KilnUniV3/file-unrecognized-param");
        }
        emit File(what, data);
    }

    function price(uint256 amount) public view returns (uint256) {
        return (yen != 0) ? quote(path, amount, uint32(scope)) * yen / WAD : 0;
    }

    /**
        @dev Permissionless price update of Kiln max acceptable price
             Requires auth on target kiln
    */
    function push() external {
        KilnBase(kiln).file("max", quote(path, KilnBase(kiln).lot(), uint32(scope)));
    }
}

