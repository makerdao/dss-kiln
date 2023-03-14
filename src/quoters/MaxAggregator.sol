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

import {IQuoter} from "src/quoters/IQuoter.sol";

contract MaxAggregator is IQuoter {
    mapping (address => uint256) public wards;
    address[] public quoters;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddQuoter(address indexed quoter);
    event RemoveQuoter(uint256 indexed index, address indexed quoter);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "MaxAggregator/not-authorized");
        _;
    }

    function _max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
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
        @dev Auth'ed function to add a quoter contract
        @param quoter   Address of the quoter contract
    */
    function addQuoter(address quoter) external auth {
        quoters.push(quoter);
        emit AddQuoter(quoter);
    }

    /**
        @dev Auth'ed function to remove a quoter contract
        @param index   Index of the quoter contract to be removed
    */
    function removeQuoter(uint256 index) external auth {
        address remove = quoters[index];
        quoters[index] = quoters[quoters.length - 1];
        quoters.pop();
        emit RemoveQuoter(index, remove);
    }

    /**
        @dev Get the amount of quoters
        @return count   Amount of quoters
    */
    function quotersCount() external view returns(uint256 count) {
        return quoters.length;
    }

    function quote(address sell, address buy, uint256 amount) external view returns (uint256 outAmount) {
        for (uint256 i; i < quoters.length; i++) {
            // Note: although sell and buy tokens are passed there is no guarantee that quoters will use/validate them
            outAmount = _max(outAmount, IQuoter(quoters[i]).quote(sell, buy, amount));
        }
    }
}
