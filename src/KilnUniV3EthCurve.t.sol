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
import "./KilnUniV3EthCurve.sol";

contract User {}

contract KilnUniV3EthCurveTest is Test {
    KilnUniV3EthCurve kiln;
    User user;

    bytes path;

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant STETH  = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant ROUTER   = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    uint256 constant WAD = 1e18;

    function setUp() public {
        user = new User();
        path = abi.encodePacked(DAI, uint24(100), USDC, uint24(500), WETH);

        kiln = new KilnUniV3EthCurve(
            DAI,
            STETH,
            WETH,
            ROUTER,
            CURVE_POOL,
            0, // send token id 0 (ETH)
            1, // receive token id 1 (stETH)
            address(user)
        );

        kiln.file("lot", 50_000 * WAD);
        kiln.file("hop", 6 hours);
        kiln.file("uniPath", path);
    }

    function mintDai(address usr, uint256 amt) internal {
        deal(DAI, usr, amt);
        assertEq(GemLike(DAI).balanceOf(address(usr)), amt);
    }

    function testFire() public {
        mintDai(address(kiln), 50_000 * WAD);
        assertEq(GemLike(DAI).balanceOf(address(kiln)), 50_000 * WAD);

        kiln.fire();

        assertEq(GemLike(DAI).balanceOf(address(kiln)), 0);
        assertTrue(GemLike(STETH).balanceOf(address(user)) > 0);
    }
}
