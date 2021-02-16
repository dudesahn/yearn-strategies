from helpers import genericStateOfStrat, genericStateOfVault
from brownie import Wei


def test_ops(token_seth, token_ecrv, strategy_ecrv, chain, vault_ecrv, voter_proxy, whale, strategist):
    token_ecrv.approve(vault_ecrv, 2 ** 256 - 1, {"from": whale})
    whalebefore = token_ecrv.balanceOf(whale)
    vault_ecrv.deposit(Wei("100 ether"), {"from": whale})
    strategy_ecrv.harvest({"from": strategist})
    assets_before = vault_ecrv.totalAssets()

    genericStateOfStrat(strategy_ecrv, token_ecrv, vault_ecrv)
    genericStateOfVault(vault_ecrv, token_ecrv)

    chain.sleep(2592000)
    chain.mine(1)

    strategy_ecrv.harvest({"from": strategist})

    print("sETH = ", token_seth.balanceOf(strategy_ecrv) / 1e18)
    print("eCRV = ", voter_proxy.balance() / 1e18)

    genericStateOfStrat(strategy_ecrv, token_ecrv, vault_ecrv)
    genericStateOfVault(vault_ecrv, token_ecrv)

    print(
        "\nEstimated APR: ", "{:.2%}".format((vault_ecrv.totalAssets() - assets_before) / assets_before * 12),
    )

    vault_ecrv.withdraw({"from": whale})
    print("\nWithdraw")
    genericStateOfStrat(strategy_ecrv, token_ecrv, vault_ecrv)
    genericStateOfVault(vault_ecrv, token_ecrv)
    print("Whale profit: ", (token_ecrv.balanceOf(whale) - whalebefore) / 1e18)


def test_migrate(token_ecrv, StrategyCurveEcrv, strategy_ecrv, chain, vault_ecrv, whale, gov, strategist):
    token_ecrv.approve(vault_ecrv, 2 ** 256 - 1, {"from": whale})
    vault_ecrv.deposit(Wei("100 ether"), {"from": whale})
    strategy_ecrv.harvest({"from": strategist})
    assets_before = vault_ecrv.totalAssets()

    genericStateOfStrat(strategy_ecrv, token_ecrv, vault_ecrv)
    genericStateOfVault(vault_ecrv, token_ecrv)

    chain.sleep(2592000)
    chain.mine(1)

    strategy_ecrv.harvest({"from": strategist})

    genericStateOfStrat(strategy_ecrv, token_ecrv, vault_ecrv)
    genericStateOfVault(vault_ecrv, token_ecrv)

    print(
        "\nEstimated APR: ", "{:.2%}".format((vault_ecrv.totalAssets() - assets_before) / assets_before * 12),
    )

    strategy_ecrv2 = strategist.deploy(StrategyCurveEcrv, vault_ecrv)
    vault_ecrv.migrateStrategy(strategy_ecrv, strategy_ecrv2, {"from": gov})
    genericStateOfStrat(strategy_ecrv, token_ecrv, vault_ecrv)
    genericStateOfStrat(strategy_ecrv2, token_ecrv, vault_ecrv)
    genericStateOfVault(vault_ecrv, token_ecrv)


def test_revoke(token_ecrv, strategy_ecrv, vault_ecrv, whale, gov, strategist):
    token_ecrv.approve(vault_ecrv, 2 ** 256 - 1, {"from": whale})
    vault_ecrv.deposit(Wei("100 ether"), {"from": whale})
    strategy_ecrv.harvest({"from": strategist})

    genericStateOfStrat(strategy_ecrv, token_ecrv, vault_ecrv)
    genericStateOfVault(vault_ecrv, token_ecrv)

    vault_ecrv.revokeStrategy(strategy_ecrv, {"from": gov})

    strategy_ecrv.harvest({"from": strategist})

    genericStateOfStrat(strategy_ecrv, token_ecrv, vault_ecrv)
    genericStateOfVault(vault_ecrv, token_ecrv)


def test_reduce_limit(token_ecrv, strategy_ecrv, vault_ecrv, whale, gov, strategist):
    token_ecrv.approve(vault_ecrv, 2 ** 256 - 1, {"from": whale})
    vault_ecrv.deposit(Wei("100 ether"), {"from": whale})
    strategy_ecrv.harvest({"from": strategist})

    dust = 3_000_000
    assert token_ecrv.balanceOf(vault_ecrv) < dust
    vault_ecrv.updateStrategyDebtRatio(strategy_ecrv, 5_000, {"from": gov})
    strategy_ecrv.harvest({"from": strategist})
    assert token_ecrv.balanceOf(vault_ecrv) > dust
