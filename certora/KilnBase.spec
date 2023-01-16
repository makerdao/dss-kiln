// KilnBase.spec

using Dai as dai
using DSToken as mkr

methods {
    wards(address) returns (uint256) envfree
    lot() returns (uint256) envfree
    hop() returns (uint256) envfree
    zzz() returns (uint256) envfree
    locked() returns (uint256) envfree
    sell() returns (address) envfree
    buy() returns (address) envfree
    dai.totalSupply() returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
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

// Verify rug function on happy path
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

// Verify rug function on reverts
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
