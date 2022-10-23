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
import "./KilnBase.sol";

contract KilnMock is KilnBase {
    bool public reenter = false;

    constructor(address _sell, address _buy) KilnBase(_sell, _buy) {}

    function setReenter() public {
        reenter = true;
    }

    function _swap(uint256) internal override returns (uint256) {
        if (reenter) this.fire();
        return 0;
    }

    function _drop(uint256) internal override {}
}

contract KilnBaseTest is Test {
    KilnMock kiln;

    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    uint256 constant WAD = 1e18;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event Rug(address indexed dst, uint256 amt);
    event Fire(uint256 indexed dai, uint256 indexed mkr);

    function setUp() public {
        kiln = new KilnMock(DAI, MKR);

        kiln.file("lot", 50_000 * WAD);
        kiln.file("hop", 6 hours);
    }

    function mintDai(address usr, uint256 amt) internal {
        deal(DAI, usr, amt);
        assertEq(GemLike(DAI).balanceOf(address(usr)), amt);
    }

    function testRely() public {
        assertEq(kiln.wards(address(123)), 0);
        vm.expectEmit(true, false, false, false);
        emit Rely(address(123));
        kiln.rely(address(123));
        assertEq(kiln.wards(address(123)), 1);
    }

    function testDeny() public {
        assertEq(kiln.wards(address(this)), 1);
        vm.expectEmit(true, false, false, false);
        emit Deny(address(this));
        kiln.deny(address(this));
        assertEq(kiln.wards(address(this)), 0);
    }

    function testRelyNonAuthed() public {
        kiln.deny(address(this));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.rely(address(123));
    }

    function testDenyNonAuthed() public {
        kiln.deny(address(this));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.deny(address(123));
    }

    function testFileLot() public {
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("lot"), 42);
        kiln.file("lot", 42);
        assertEq(kiln.lot(), 42);
    }

    function testFileHop() public {
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("hop"), 314);
        kiln.file("hop", 314);
        assertEq(kiln.hop(), 314);
    }

    function testFileUnrecognized() public {
        vm.expectRevert("KilnBase/file-unrecognized-param");
        kiln.file("nonsense", 23);
    }

    function testFileLotNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.file("lot", 42);
    }

    function testFileHopNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.file("hop", 314);
    }

    function testRug() public {
        mintDai(address(kiln), 50_000 * WAD);

        assertEq(kiln.sell(), DAI);
        assertEq(GemLike(DAI).balanceOf(address(kiln)), 50_000 * WAD);
        assertEq(GemLike(DAI).balanceOf(address(this)), 0);

        vm.expectEmit(true, true, false, false);
        emit Rug(address(this), 50_000 * WAD);
        kiln.rug(address(this));

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 0);
        assertEq(GemLike(DAI).balanceOf(address(this)), 50_000 * WAD);
    }

    function testRugNonAuthed() public {
        vm.startPrank(address(123));
        vm.expectRevert("KilnBase/not-authorized");
        kiln.rug(address(this));
    }

    function testFire() public {
        mintDai(address(kiln), 50_000 * WAD);
        vm.expectEmit(true, true, false, false);
        emit Fire(50_000 * WAD, 0);
        kiln.fire();
    }

    function testFireNoBalance() public {
        assertEq(kiln.sell(), DAI);
        mintDai(address(kiln), 0);
        vm.expectRevert("KilnBase/no-balance");
        kiln.fire();
    }

    function testFireAfterHopPassed() public {
        mintDai(address(kiln), 50_000 * WAD);
        kiln.fire();
        skip(kiln.hop());
        kiln.fire();
    }

    function testFireAfterHopNotPassed() public {
        mintDai(address(kiln), 50_000 * WAD);
        kiln.fire();
        skip(kiln.hop() - 1 seconds);
        vm.expectRevert("KilnBase/fired-too-soon");
        kiln.fire();
    }

    function testFireReenter() public {
        mintDai(address(kiln), 50_000 * WAD);
        kiln.setReenter();
        vm.expectRevert("KilnBase/system-locked");
        kiln.fire();
    }
}
