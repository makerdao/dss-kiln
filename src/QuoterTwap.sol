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

import {TwapProduct} from "./uniV3/TwapProduct.sol";

// TODO: implement quoter interface?
contract QuoterTwap is TwapProduct {
    mapping (address => uint256) public wards;

    uint256 public scope; // [Seconds]  Time period for TWAP calculations
    bytes   public path;  //            ABI-encoded UniV3 compatible path

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, bytes data);

    // TODO: consider merging with TwapProduct
    // TODO: documentation ?
    constructor(address _uniV3Factory) TwapProduct(_uniV3Factory)
    {
        scope = 1 hours;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "QuoterTwap/not-authorized");
        _;
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

    // TODO: documentation
    function file(bytes32 what, uint256 data) external auth {
        if (what == "scope") {
            require(data > 0, "QuoterTwap/zero-scope");
            require(data <= uint32(type(int32).max), "Recipe2/scope-overflow");
            scope = data;
        } else revert("QuoterTwap/file-unrecognized-param");
        emit File(what, data);
    }

    /**
        @dev Auth'ed function to update path value
        @param what   Tag of value to update
        @param data   Value to update
    */
    function file(bytes32 what, bytes calldata data) external auth {
        if (what == "path") path = data;
        else revert("QuoterTwap/file-unrecognized-param");
        emit File(what, data);
    }

    function quote(address, address, uint256 amount) external view returns (uint256 outAMount) {
        outAMount = quote(path, amount, uint32(scope));
    }
}
