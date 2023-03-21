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

import "forge-std/Test.sol";
import "src/quoters/MaxAggregator.sol";

contract AggregatorTest is Test {
    MaxAggregator aggregator;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddQuoter(address indexed quoter);
    event RemoveQuoter(uint256 indexed index, address indexed quoter);

    function setUp() public {
        aggregator = new MaxAggregator();
    }

    function testRely() public {
        assertEq(aggregator.wards(address(123)), 0);
        vm.expectEmit(true, false, false, false);
        emit Rely(address(123));
        aggregator.rely(address(123));
        assertEq(aggregator.wards(address(123)), 1);
    }

    function testDeny() public {
        assertEq(aggregator.wards(address(this)), 1);
        vm.expectEmit(true, false, false, false);
        emit Deny(address(this));
        aggregator.deny(address(this));
        assertEq(aggregator.wards(address(this)), 0);
    }

    function testRelyNonAuthed() public {
        aggregator.deny(address(this));
        vm.expectRevert("MaxAggregator/not-authorized");
        aggregator.rely(address(123));
    }

    function testDenyNonAuthed() public {
        aggregator.deny(address(this));
        vm.expectRevert("MaxAggregator/not-authorized");
        aggregator.deny(address(123));
    }

    function testAddRemoveQuoter() public {
        vm.expectEmit(true, true, false, false);
        emit AddQuoter(address(1));
        aggregator.addQuoter(address(1));
        assertEq(aggregator.quoters(0), address(1));
        assertEq(aggregator.quotersCount(), 1);

        vm.expectEmit(true, true, false, false);
        emit AddQuoter(address(2));
        aggregator.addQuoter(address(2));
        assertEq(aggregator.quoters(0), address(1));
        assertEq(aggregator.quoters(1), address(2));
        assertEq(aggregator.quotersCount(), 2);

        vm.expectEmit(true, true, false, false);
        emit AddQuoter(address(3));
        aggregator.addQuoter(address(3));
        assertEq(aggregator.quoters(0), address(1));
        assertEq(aggregator.quoters(1), address(2));
        assertEq(aggregator.quoters(2), address(3));
        assertEq(aggregator.quotersCount(), 3);

        vm.expectEmit(true, true, false, false);
        emit AddQuoter(address(4));
        aggregator.addQuoter(address(4));
        assertEq(aggregator.quoters(0), address(1));
        assertEq(aggregator.quoters(1), address(2));
        assertEq(aggregator.quoters(2), address(3));
        assertEq(aggregator.quoters(3), address(4));
        assertEq(aggregator.quotersCount(), 4);

        // Remove in the middle
        vm.expectEmit(true, true, false, false);
        emit RemoveQuoter(2, address(3));
        aggregator.removeQuoter(2);
        assertEq(aggregator.quoters(0), address(1));
        assertEq(aggregator.quoters(1), address(2));
        assertEq(aggregator.quoters(2), address(4));
        assertEq(aggregator.quotersCount(), 3);

        // Remove last
        vm.expectEmit(true, true, false, false);
        emit RemoveQuoter(2, address(4));
        aggregator.removeQuoter(2);
        assertEq(aggregator.quoters(0), address(1));
        assertEq(aggregator.quoters(1), address(2));
        assertEq(aggregator.quotersCount(), 2);

        // Remove first
        vm.expectEmit(true, true, false, false);
        emit RemoveQuoter(0, address(1));
        aggregator.removeQuoter(0);
        assertEq(aggregator.quoters(0), address(2));
        assertEq(aggregator.quotersCount(), 1);

        // Remove single
        vm.expectEmit(true, true, false, false);
        emit RemoveQuoter(0, address(2));
        aggregator.removeQuoter(0);
        assertEq(aggregator.quotersCount(), 0);
    }

    function testAddQuoterNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("MaxAggregator/not-authorized");
        aggregator.addQuoter(address(7));
    }

    function testRemoveQuoterNonAuthed() public {
        aggregator.addQuoter(address(7));

        vm.startPrank(address(123));
        vm.expectRevert("MaxAggregator/not-authorized");
        aggregator.removeQuoter(0);
    }
}
