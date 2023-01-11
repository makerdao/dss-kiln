// KilnBase.spec

methods {
    wards(address) returns (uint256) envfree
    lot() returns (uint256) envfree
    hop() returns (uint256) envfree
    zzz() returns (uint256) envfree
    locked() returns (uint256) envfree
    sell() returns (address) envfree
    buy() returns (address) envfree
}

// Verify fallback always reverts
// In this case is pretty important as we are filtering it out from some invariants/rules
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
