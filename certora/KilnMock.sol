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

import {KilnBase, GemLike} from "../src/KilnBase.sol";

interface GemMock is GemLike {
    function burn(uint256) external;
    function transferFrom(address, address, uint256) external returns (bool);
}

contract KilnMock is KilnBase {

    address public immutable pool;

    constructor(
        address _sell,
        address _buy,
        address _pool
    )
        KilnBase(_sell, _buy)
    {
        pool = _pool;
    }

    function _swap(uint256 amount) internal override returns (uint256 swapped) {
        GemMock(sell).transfer(pool, amount);
        GemMock(buy).transferFrom(pool, address(this), amount);
        swapped = amount;
    }

    function _drop(uint256 amount) internal override {
        GemMock(buy).burn(amount);
    }
}
