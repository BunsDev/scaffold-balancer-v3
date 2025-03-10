// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    LiquidityManagement,
    PoolRoleAccounts,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
// import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.sol";

import { ConstantSumFactory } from "../contracts/pools/ConstantSumFactory.sol";
import { ConstantSumPool } from "../contracts/pools/ConstantSumPool.sol";

contract ConstantSumPoolTest is BasePoolTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    uint256 daiIdx;
    uint256 usdcIdx;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT;
        tokenAmountIn = TOKEN_AMOUNT / 4;

        BasePoolTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createPool() internal override returns (address) {
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        factory = new ConstantSumFactory(IVault(address(vault)), 365 days);
        PoolRoleAccounts memory roleAccounts;
        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));
        LiquidityManagement memory liquidityManagement;

        ConstantSumPool newPool = ConstantSumPool(
            ConstantSumFactory(address(factory)).create(
                "Constant Sum Pool", // name
                "CSP", // symbol
                ZERO_BYTES32, // salt
                vault.buildTokenConfig(sortedTokens), // TokenConfig[]
                DEFAULT_SWAP_FEE, // swapFeePercentage
                false, // protocolFeeExempt
                roleAccounts,
                poolHooksContract,
                liquidityManagement
            )
        );
        return address(newPool);
    }

    function initPool() internal override {
        vm.startPrank(lp);
        bptAmountOut = _initPool(
            pool,
            tokenAmounts,
            // Account for the precision loss
            expectedAddLiquidityBptAmountOut - DELTA
        );
        vm.stopPrank();
    }

    // function testGetBptRate() public {
    //     uint256 invariantBefore = WeightedMath.computeInvariant(weights, [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray());
    //     uint256 invariantAfter = WeightedMath.computeInvariant(
    //         weights,
    //         [2 * TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray()
    //     );

    //     uint256[] memory amountsIn = [TOKEN_AMOUNT, 0].toMemoryArray();
    //     _testGetBptRate(invariantBefore, invariantAfter, amountsIn);
    // }

    function testFailSwapFeeTooLow() public {
        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        tokenConfigs[daiIdx].token = IERC20(dai);
        tokenConfigs[usdcIdx].token = IERC20(usdc);

        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        address lowFeeWeightedPool = ConstantSumFactory(address(factory)).create(
            "Constant Sum Pool",
            "CSP",
            ZERO_BYTES32,
            tokenConfigs,
            MIN_SWAP_FEE - 1, // Swap fee too low
            false, // protocolFeeExempt
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        vm.expectRevert(IVaultErrors.SwapFeePercentageTooLow.selector);
        factoryMock.registerTestPool(lowFeeWeightedPool, tokenConfigs);
    }
}
