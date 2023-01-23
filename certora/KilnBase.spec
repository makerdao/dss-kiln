// KilnBase.spec

using Dai as dai
using DSToken as token
using MockAuthority as authority
using PoolMock as pool

methods {
    wards(address) returns (uint256) envfree
    lot() returns (uint256) envfree
    hop() returns (uint256) envfree
    zzz() returns (uint256) envfree
    locked() returns (uint256) envfree
    sell() returns (address) envfree
    buy() returns (address) envfree
    pool() returns (address) envfree
    dai.totalSupply() returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
    dai.allowance(address, address) returns (uint256) envfree
    token.authority() returns (address) envfree
    token.owner() returns (address) envfree
    token.stopped() returns (bool) envfree
    token.totalSupply() returns (uint256) envfree
    token.balanceOf(address) returns (uint256) envfree
    token.allowance(address, address) returns (uint256) envfree
    pool.dai() returns (address) envfree
    pool.token() returns (address) envfree
}

definition min(uint256 x, uint256 y) returns uint256 = x <= y ? x : y;

ghost lockedGhost() returns uint256;

hook Sstore locked uint256 n_locked STORAGE {
    havoc lockedGhost assuming lockedGhost@new() == n_locked;
}

hook Sload uint256 value locked STORAGE {
    require lockedGhost() == value;
}

// Verify fallback always reverts
rule fallback_revert(method f) filtered { f -> f.isFallback } {
    env e;

    calldataarg arg;
    f@withrevert(e, arg);

    assert(lastReverted, "assert1 failed");
}

// Verify that wards behaves correctly on rely
rule rely(address usr) {
    env e;

    address other;

    require(other != usr);

    uint256 wardOtherBefore = wards(other);

    rely(e, usr);

    uint256 wardAfter = wards(usr);
    uint256 wardOtherAfter = wards(other);

    assert(wardAfter == 1, "assert1 failed");
    assert(wardOtherAfter == wardOtherBefore, "assert2 failed");
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    uint256 ward = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");

    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

// Verify that wards behaves correctly on deny
rule deny(address usr) {
    env e;

    address other;

    require(other != usr);

    uint256 wardOtherBefore = wards(other);

    deny(e, usr);

    uint256 wardAfter = wards(usr);
    uint256 wardOtherAfter = wards(other);

    assert(wardAfter == 0, "assert1 failed");
    assert(wardOtherAfter == wardOtherBefore, "assert2 failed");
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    uint256 ward = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");

    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

// Verify correct storage changes for not reverting file
rule file(bytes32 what, uint256 data) {
    env e;

    uint256 lotBefore = lot();
    uint256 hopBefore = hop();

    file(e, what, data);

    uint256 lotAfter = lot();
    uint256 hopAfter = hop();

    assert(what == 0x6c6f740000000000000000000000000000000000000000000000000000000000 => lotAfter == data,      "assert1 failed");
    assert(what != 0x6c6f740000000000000000000000000000000000000000000000000000000000 => lotAfter == lotBefore, "assert2 failed");
    assert(what == 0x686f700000000000000000000000000000000000000000000000000000000000 => hopAfter == data,      "assert3 failed");
    assert(what != 0x686f700000000000000000000000000000000000000000000000000000000000 => hopAfter == hopBefore, "assert4 failed");
}

// Verify revert rules on file
rule file_revert(bytes32 what, uint256 data) {
    env e;

    uint256 ward = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = what != 0x6c6f740000000000000000000000000000000000000000000000000000000000 && // what is not "lot"
                   what != 0x686f700000000000000000000000000000000000000000000000000000000000;   // what is not "hop"

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify correct storage changes for not reverting rug
rule rug(address dst) {
    env e;

    require(dai == sell());

    uint256 balanceKilnBefore = dai.balanceOf(currentContract);
    uint256 balanceDstBefore = dai.balanceOf(dst);
    uint256 supplyBefore = dai.totalSupply();
    bool dstSameAsKiln = currentContract == dst;

    rug(e, dst);

    uint256 balanceKilnAfter = dai.balanceOf(currentContract);
    uint256 balanceDstAfter = dai.balanceOf(dst);
    uint256 supplyAfter = dai.totalSupply();

    assert(supplyAfter == supplyBefore, "assert1 failed");
    assert(!dstSameAsKiln =>
            balanceKilnAfter == 0 &&
            balanceKilnBefore == (balanceDstAfter - balanceDstBefore), "assert2 failed");
    assert(dstSameAsKiln => balanceKilnAfter == balanceKilnBefore, "assert3 failed");
}

// Verify revert rules on rug
rule rug_revert(address dst) {
    env e;

    require(dai == sell());

    uint256 ward = wards(e.msg.sender);
    uint256 locked = lockedGhost();

    uint256 balanceKiln = dai.balanceOf(currentContract);
    uint256 balanceDst = dai.balanceOf(dst);

    bool dstSameAsKiln = currentContract == dst;

    rug@withrevert(e, dst);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = locked != 0;
    bool revert4 = !dstSameAsKiln && balanceKiln + balanceDst > max_uint256;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4, "Revert rules are not covering all the cases");
}

// Verify correct storage changes for not reverting fire
rule fire() {
    env e;

    require(dai == sell());
    require(pool.dai() == dai);
    require(token == buy());
    require(pool.token() == token);
    require(pool == pool());

    uint256 daiBalanceKilnBefore = dai.balanceOf(currentContract);
    uint256 daiBalancePoolBefore = dai.balanceOf(pool);
    uint256 tokenBalanceKilnBefore = token.balanceOf(currentContract);
    uint256 tokenBalancePoolBefore = token.balanceOf(pool);
    uint256 daiSupplyBefore = dai.totalSupply();
    uint256 tokenSupplyBefore = token.totalSupply();
    uint256 lot = lot();

    uint256 minAmt = min(daiBalanceKilnBefore, lot);

    fire(e);

    uint256 daiBalanceKilnAfter = dai.balanceOf(currentContract);
    uint256 daiBalancePoolAfter = dai.balanceOf(pool);
    uint256 tokenBalanceKilnAfter = token.balanceOf(currentContract);
    uint256 tokenBalancePoolAfter = token.balanceOf(pool);
    uint256 daiSupplyAfter = dai.totalSupply();
    uint256 tokenSupplyAfter = token.totalSupply();
    uint256 zzzAfter = zzz();

    assert(daiSupplyAfter == daiSupplyBefore,                          "assert1 failed");
    assert(daiBalanceKilnAfter == (daiBalanceKilnBefore - minAmt),     "assert2 failed");
    assert(daiBalancePoolAfter == (daiBalancePoolBefore + minAmt),     "assert3 failed");
    assert(tokenBalancePoolAfter == (tokenBalancePoolBefore - minAmt), "assert4 failed");
    assert(tokenSupplyAfter == (tokenSupplyBefore - minAmt),           "assert5 failed");
    assert(zzzAfter == e.block.timestamp,                              "assert6 failed");
    assert(tokenBalanceKilnAfter == tokenBalanceKilnBefore,            "assert7 failed");
}

// Verify revert rules on fire
rule fire_revert() {
    env e;

    require(dai == sell());
    require(token == buy());
    require(authority == token.authority());
    require(pool == pool());

    uint256 locked = lockedGhost();

    bool stop = token.stopped();
    address tokenOwner = token.owner();
    bool canCall = authority.canCall(e, currentContract, token, 0x42966c6800000000000000000000000000000000000000000000000000000000); // burn(uint256)

    uint256 daiBalanceKiln = dai.balanceOf(currentContract);
    uint256 daiBalancePool = dai.balanceOf(pool);
    uint256 daiAllowed = dai.allowance(currentContract, pool);
    uint256 tokenBalanceKiln = token.balanceOf(currentContract);
    uint256 tokenBalancePool = token.balanceOf(pool);
    uint256 tokenAllowed = token.allowance(currentContract, pool);
    uint256 tokenSupply = token.totalSupply();
    uint256 zzz = zzz();
    uint256 hop = hop();
    uint256 lot = lot();

    uint256 minAmt = min(daiBalanceKiln, lot);

    fire@withrevert(e);

    bool revert1  = e.msg.value > 0;
    bool revert2  = locked != 0;
    bool revert3  = e.block.timestamp < zzz + hop;
    bool revert4  = minAmt == 0;
    bool revert5  = daiAllowed != max_uint256 && daiAllowed - minAmt > max_uint256;
    bool revert6  = daiBalanceKiln - minAmt > max_uint256;
    bool revert7  = daiBalancePool + minAmt > max_uint256;
    bool revert8  = tokenBalancePool < minAmt;
    bool revert9  = tokenBalanceKiln + minAmt > max_uint256;
    bool revert10 = tokenBalancePool - minAmt > max_uint256;
    bool revert11 = tokenBalanceKiln > max_uint256;
    bool revert12 = tokenSupply - minAmt > max_uint256;
    bool revert13 = tokenAllowed != max_uint256 && tokenAllowed - minAmt > max_uint256;
    bool revert14 = stop == true;
    bool revert15 = currentContract != token && currentContract != tokenOwner && (authority == 0 || !canCall);

    assert(revert1  => lastReverted, "revert1  failed");
    assert(revert2  => lastReverted, "revert2  failed");
    assert(revert3  => lastReverted, "revert3  failed");
    assert(revert4  => lastReverted, "revert4  failed");
    assert(revert5  => lastReverted, "revert5  failed");
    assert(revert6  => lastReverted, "revert6  failed");
    assert(revert7  => lastReverted, "revert7  failed");
    assert(revert8  => lastReverted, "revert8  failed");
    assert(revert9  => lastReverted, "revert9  failed");
    assert(revert10 => lastReverted, "revert10 failed");
    assert(revert11 => lastReverted, "revert11 failed");
    assert(revert12 => lastReverted, "revert12 failed");
    assert(revert13 => lastReverted, "revert13 failed");
    assert(revert14 => lastReverted, "revert14 failed");
    assert(revert15 => lastReverted, "revert15 failed");

    assert(lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11 || revert12 ||
                           revert13 || revert14 || revert15, "Revert rules are not covering all the cases");
}
