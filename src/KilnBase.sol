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

interface GemLike {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
}

abstract contract KilnBase {
    mapping (address => uint256) public wards;

    uint256 public lot;    // [WAD]        Amount of token to sell
    uint256 public hop;    // [Seconds]    Time between sales
    uint256 public zzz;    // [Timestamp]  Last trade
    uint256 public locked;

    address public immutable sell;
    address public immutable buy;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event Rug(address indexed dst, uint256 amt);
    event Fire(uint256 indexed amt, uint256 indexed swapped);

    constructor(address _sell, address _buy) {
        sell = _sell;
        buy  = _buy;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "KilnBase/not-authorized");
        _;
    }

    modifier lock {
        require(locked == 0, "KilnBase/system-locked");
        locked = 1;
        _;
        locked = 0;
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }

    /**
        @dev Auth'ed function to authorize an address for privileged functions
        @param usr   Address to be authorized
    */
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }

    /**
        @dev Auth'ed function to un-authorize an address for privileged functions
        @param usr   Address to be un-authorized
    */
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    /**
        @dev Auth'ed function to update lot or hop values
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, uint256 data) public virtual auth {
        if      (what == "lot") lot = data;
        else if (what == "hop") hop = data;
        else revert("KilnBase/file-unrecognized-param");
        emit File(what, data);
    }

    /**
        @dev Auth'ed function to withdraw unspent funds
        @param dst   Destination of the funds
    */
    function rug(address dst) external auth {
        uint256 amt = GemLike(sell).balanceOf(address(this));
        GemLike(sell).transfer(dst, amt);
        emit Rug(dst, amt);
    }

    /**
        @dev Function to execute swap/drop and reset zzz if enough time has passed
    */
    function fire() external lock {
        require(block.timestamp >= zzz + hop, "KilnBase/fired-too-soon");
        uint256 amt = _min(GemLike(sell).balanceOf(address(this)), lot);
        require(amt > 0, "KilnBase/no-balance");
        uint256 swapped = _swap(amt);
        zzz = block.timestamp;
        _drop(swapped);
        emit Fire(amt, swapped);
    }

    /**
        @dev Override this to implement swap logic
     */
    function _swap(uint256 amount) virtual internal returns (uint256 swapped);

    /**
        @dev Override this to implement some other disposition
     */
    function _drop(uint256 amount) virtual internal;
}
