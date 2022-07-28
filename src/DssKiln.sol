// SPDX-License-Identifier: GPL-3.0-or-later
//
// DssKiln - Asset acquisition and control module
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

interface GemLike {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function burn(uint256) external;
    function transfer(address, uint256) external;
}

abstract contract DssKiln {

    // --- Auth ---
    mapping (address => uint256) public wards;

    uint256 public           lot;  // [WAD]        Amount of token to sell
    uint256 public           hop;  // [Seconds]    Time between sales
    uint256 public           zzz;  // [Timestamp]  Last trade
    address public immutable sell;
    address public immutable buy;

    uint256 internal locked;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event Fire(uint256 indexed dai, uint256 indexed mkr);

    /**
        @dev Base contract constructor
    */
    constructor(address _sell, address _buy) {
        sell = _sell;
        buy  = _buy;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "DssKiln/not-authorized");
        _;
    }

    // --- Mutex  ---
    modifier lock {
        require(locked == 0, "DssKiln/system-locked");
        locked = 1;
        _;
        locked = 0;
    }

    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }

    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    /**
        @dev Auth'ed function to update lot or hop values
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, uint256 data) external auth {
        if      (what == "lot") lot = data;
        else if (what == "hop") hop = data;
        else revert("DssKiln/file-unrecognized-param");
        emit File(what, data);
    }

    function fire() external lock {
        require(block.timestamp >= _add(zzz, hop), "DssKiln/fired-too-soon");
        uint256 _amt = _min(GemLike(sell).balanceOf(address(this)), lot);
        require(_amt > 0, "DssKiln/no-balance");
        uint256 _swapped = _swap(_amt);
        zzz = block.timestamp;
        _drop(_swapped);
        emit Fire(_amt, _swapped);
    }

    /**
        @dev Override this to implement swap logic
     */
    function _swap(uint256 _amount) virtual internal returns (uint256 _swapped);

    /**
        @dev Override in inherited contract to implement some other disposition.
     */
    function _drop(uint256 _amount) virtual internal;
}
