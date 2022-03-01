// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./DssKiln.sol";

contract DssKilnTest is DSTest {
    DssKiln kiln;

    function setUp() public {
        kiln = new DssKiln();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
