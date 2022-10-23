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

import {KilnMom}           from "./KilnMom.sol";
import {KilnBase, GemLike} from "./KilnBase.sol";

contract KilnMock is KilnBase {
    constructor(address _sell, address _buy) KilnBase(_sell, _buy) {}

    function _swap(uint256) internal override pure returns (uint256) { return 0; }
    function _drop(uint256) internal override {}
}

contract AuthorityMock {
    function canCall(address src, address, bytes4 sig) external pure returns (bool) {
        return src == address(789) && sig == KilnMom.rug.selector;
    }
}

contract KilnMomTest is Test {
    KilnMock kiln;
    KilnMom mom;

    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    uint256 constant WAD = 1e18;

    event SetOwner(address indexed newOwner);
    event SetAuthority(address indexed newAuthority);
    event Rug(address indexed who, address indexed dst);

    function setUp() public {
        kiln = new KilnMock(DAI, MKR);

        kiln.file("lot", 50_000 * WAD);
        kiln.file("hop", 6 hours);

        mom = new KilnMom();
        mom.setAuthority(address(new AuthorityMock()));
        kiln.rely(address(mom));
    }

    function mintDai(address usr, uint256 amt) internal {
        deal(DAI, usr, amt);
        assertEq(GemLike(DAI).balanceOf(address(usr)), amt);
    }

    function testSetOwner() public {
        vm.expectEmit(true, false, false, false);
        emit SetOwner(address(123));
        mom.setOwner(address(123));
        assertEq(mom.owner(), address(123));
    }

    function testSetOwnerNonAuthed() public {
        vm.startPrank(address(456));
        vm.expectRevert("KilnMom/only-owner");
        mom.setOwner(address(123));
    }

    function testSetAuthority() public {
        vm.expectEmit(true, false, false, false);
        emit SetAuthority(address(123));
        mom.setAuthority(address(123));
        assertEq(mom.authority(), address(123));
    }

    function testSetAuthorityNonAuthed() public {
        vm.startPrank(address(456));
        vm.expectRevert("KilnMom/only-owner");
        mom.setAuthority(address(123));
    }

    function testRugFromOwner() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(kiln.sell(), DAI);
        assertEq(GemLike(DAI).balanceOf(address(kiln)), 50_000 * WAD);

        vm.expectEmit(true, true, false, false);
        emit Rug(address(kiln), address(this));
        mom.rug(address(kiln), address(this));

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 0);
        assertEq(GemLike(DAI).balanceOf(address(mom)), 0);
        assertEq(GemLike(DAI).balanceOf(address(this)), 50_000 * WAD);
    }

    function testRugWithAuthority() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(kiln.sell(), DAI);
        assertEq(GemLike(DAI).balanceOf(address(kiln)), 50_000 * WAD);

        vm.prank(address(789));
        vm.expectEmit(true, false, false, false);
        emit Rug(address(kiln), address(this));
        mom.rug(address(kiln), address(this));

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 0);
        assertEq(GemLike(DAI).balanceOf(address(mom)), 0);
        assertEq(GemLike(DAI).balanceOf(address(this)), 50_000 * WAD);
    }

    function testRugNonAuthed() public {
        vm.startPrank(address(456));
        vm.expectRevert("KilnMom/not-authorized");
        mom.rug(address(kiln), address(this));
    }
}
