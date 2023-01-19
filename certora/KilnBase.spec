// KilnBase.spec

using Dai as dai
using DSToken as mkr
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
    mkr.authority() returns (address) envfree
    mkr.owner() returns (address) envfree
    mkr.stopped() returns (bool) envfree
    mkr.totalSupply() returns (uint256) envfree
    mkr.balanceOf(address) returns (uint256) envfree
}

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

    assert(lastReverted, "Fallback did not revert");
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

    assert(wardAfter == 1, "rely did not set wards as expected");
    assert(wardOtherAfter == wardOtherBefore, "rely affected other wards which was not expected");
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

    assert(wardAfter == 0, "deny did not set wards as expected");
    assert(wardOtherAfter == wardOtherBefore, "deny affected other wards which was not expected");
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

    assert(what == 0x6c6f740000000000000000000000000000000000000000000000000000000000 => lotAfter == data, "file did not set lot as expected");
    assert(what != 0x6c6f740000000000000000000000000000000000000000000000000000000000 => lotAfter == lotBefore, "file did not keep unchanged lot");
    assert(what == 0x686f700000000000000000000000000000000000000000000000000000000000 => hopAfter == data, "file did not set hop as expected");
    assert(what != 0x686f700000000000000000000000000000000000000000000000000000000000 => hopAfter == hopBefore, "file did not keep unchanged hop");
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

    assert(supplyAfter == supplyBefore, "supply did not remain as expected");
    assert(!dstSameAsKiln => balanceKilnAfter == 0 && balanceKilnBefore == (balanceDstAfter - balanceDstBefore), "balance did not change as expected");
    assert(dstSameAsKiln => balanceKilnAfter == balanceKilnBefore, "balance changed");
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

    require(dai  == sell());
    require(mkr  == buy());
    require(pool == pool());

    uint256 daiBalanceKilnBefore = dai.balanceOf(currentContract);
    uint256 daiBalancePoolBefore = dai.balanceOf(pool);
    uint256 mkrBalanceKilnBefore = mkr.balanceOf(currentContract);
    uint256 mkrBalancePoolBefore = mkr.balanceOf(pool);
    uint256 daiSupplyBefore = dai.totalSupply();
    uint256 mkrSupplyBefore = mkr.totalSupply();
    uint256 lot = lot();

    fire(e);

    uint256 daiBalanceKilnAfter = dai.balanceOf(currentContract);
    uint256 daiBalancePoolAfter = dai.balanceOf(pool);
    uint256 mkrBalanceKilnAfter = mkr.balanceOf(currentContract);
    uint256 mkrBalancePoolAfter = mkr.balanceOf(pool);
    uint256 daiSupplyAfter = dai.totalSupply();
    uint256 mkrSupplyAfter = mkr.totalSupply();
    uint256 zzzAfter = zzz();

    assert(daiSupplyAfter == daiSupplyBefore,                                       "assert 1 failed");
    assert(daiBalanceKilnBefore > lot =>
            daiBalanceKilnAfter == (daiBalanceKilnBefore - lot) &&
            daiBalancePoolAfter == (daiBalancePoolBefore + lot) &&
            mkrBalancePoolAfter == (mkrBalancePoolBefore - lot) &&
            mkrSupplyAfter      == (mkrSupplyBefore - lot),                         "assert 2 failed");
    assert(daiBalanceKilnBefore <= lot =>
            daiBalanceKilnAfter == 0 &&
            daiBalancePoolAfter == (daiBalancePoolBefore + daiBalanceKilnBefore) &&
            mkrBalancePoolAfter == (mkrBalancePoolBefore - daiBalanceKilnBefore) &&
            mkrSupplyAfter      == (mkrSupplyBefore - daiBalanceKilnBefore),        "assert 3 failed");
    assert(zzzAfter == e.block.timestamp,                                           "assert 4 failed");
    assert(mkrBalanceKilnAfter == mkrBalanceKilnBefore,                             "assert 5 failed");
}

// Verify revert rules on fire
rule fire_revert() {
    env e;

    require(dai  == sell());
    require(mkr  == buy());
    require(authority == mkr.authority());
    require(pool == pool());

    uint256 locked = lockedGhost();

    bool stop = mkr.stopped();
    address tokenOwner = mkr.owner();
    bool canCall = authority.canCall(e, currentContract, mkr, 0x40c10f1900000000000000000000000000000000000000000000000000000000);

    uint256 daiBalanceKiln = dai.balanceOf(currentContract);
    uint256 daiBalancePool = dai.balanceOf(pool);
    uint256 mkrBalanceKiln = mkr.balanceOf(currentContract);
    uint256 mkrBalancePool = mkr.balanceOf(pool);
    uint256 mkrSupply = mkr.totalSupply();
    uint256 zzz = zzz();
    uint256 hop = hop();
    uint256 lot = lot();

    fire@withrevert(e);

    bool revert1  = e.msg.value > 0;
    bool revert2  = locked != 0;
    bool revert3  = e.block.timestamp < zzz + hop;
    bool revert4  = daiBalanceKiln >  lot && lot == 0;
    bool revert5  = daiBalanceKiln <= lot && daiBalanceKiln == 0;
    bool revert6  = daiBalanceKiln >  lot && daiBalancePool + lot > max_uint256;
    bool revert7  = daiBalanceKiln >  lot && mkrBalancePool < lot;
    bool revert8  = daiBalanceKiln <= lot && mkrBalancePool < daiBalanceKiln;
    bool revert9  = daiBalanceKiln >  lot && mkrBalanceKiln + lot > max_uint256;
    bool revert10 = daiBalanceKiln <= lot && mkrBalanceKiln + daiBalanceKiln > max_uint256;
    bool revert11 = daiBalanceKiln >  lot && mkrBalancePool - lot > mkrBalancePool;
    bool revert12 = daiBalanceKiln <= lot && mkrBalancePool - daiBalanceKiln > mkrBalancePool;
    bool revert13 = daiBalanceKiln >  lot && mkrBalanceKiln - lot > mkrBalanceKiln;
    bool revert14 = daiBalanceKiln <= lot && mkrBalanceKiln - daiBalanceKiln > mkrBalanceKiln;
    bool revert15 = daiBalanceKiln >  lot && mkrSupply - lot > mkrSupply;
    bool revert16 = daiBalanceKiln <= lot && mkrSupply - daiBalanceKiln > mkrSupply;
    bool revert17 = stop == true;
    bool revert18 = currentContract != mkr && currentContract != tokenOwner && (authority == 0 || !canCall);


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
    assert(revert16 => lastReverted, "revert16 failed");
    assert(revert17 => lastReverted, "revert17 failed");
    assert(revert18 => lastReverted, "revert18 failed");

    assert(lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11 || revert12 ||
                           revert13 || revert14 || revert15 ||
                           revert16 || revert17 || revert18, "Revert rules are not covering all the cases");
}
