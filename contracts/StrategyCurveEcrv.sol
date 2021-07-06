// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {ICurveFi} from "../interfaces/curve.sol";
import {IUniswapV2Router02} from "../interfaces/uniswap.sol";
import {StrategyProxy} from "../interfaces/yearn.sol";

contract StrategyCurveEcrv is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant gauge =
        address(0x3C0FFFF15EA30C35d7A85B85c0782D6c94e1d238);
    address public constant voter =
        address(0xF147b8125d2ef93FB6965Db97D6746952a133934); // Yearn's veCRV voter

    address private constant uniswapRouter =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address private constant sushiswapRouter =
        address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    address public dex = address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F); // default SushiSwap
    address[] public crvPathWeth;

    uint256 public keepCRV = 1000;
    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant minToSwap = 1e9; // 1 gwei

    ICurveFi public curveStableSwap =
        ICurveFi(address(0xc5424B857f758E906013F3555Dad202e4bdB4567)); // Curve ETH/sETH StableSwap pool contract
    StrategyProxy public proxy =
        StrategyProxy(address(0x9a165622a744C20E3B2CB443AeD98110a33a231b));

    IERC20 public weth =
        IERC20(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IERC20 public sEth =
        IERC20(address(0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb));
    IERC20 public crv =
        IERC20(address(0xD533a949740bb3306d119CC777fa900bA034cd52));

    constructor(address _vault) public BaseStrategy(_vault) {
        want.safeApprove(address(proxy), uint256(-1));
        crv.safeApprove(uniswapRouter, uint256(-1));
        crv.safeApprove(sushiswapRouter, uint256(-1));

        crvPathWeth = new address[](2);
        crvPathWeth[0] = address(crv);
        crvPathWeth[1] = address(weth);

        minReportDelay = 4 hours;
        maxReportDelay = 8 hours;
        debtThreshold = 2e21;
    }

    function name() external view override returns (string memory) {
        return "CurveeCRVVoterProxy";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return proxy.balanceOf(gauge);
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 gaugeTokens = proxy.balanceOf(gauge);
        if (gaugeTokens > 0) {
            uint256 startingWantBalance = balanceOfWant();
            proxy.harvest(gauge);

            uint256 crvBalance = crv.balanceOf(address(this));
            if (crvBalance > minToSwap) {
                uint256 keepCrv = crvBalance.mul(keepCRV).div(DENOMINATOR);
                crv.safeTransfer(voter, keepCrv);

                crvBalance = crv.balanceOf(address(this));
                IUniswapV2Router02(dex).swapExactTokensForETH(
                    crvBalance,
                    uint256(0),
                    crvPathWeth,
                    address(this),
                    now
                );
            }

            uint256 ethBalance = address(this).balance;
            if (ethBalance > minToSwap) {
                curveStableSwap.add_liquidity{value: ethBalance}(
                    [ethBalance, 0],
                    0
                );
            }

            _profit = balanceOfWant().sub(startingWantBalance);
        }

        if (_debtOutstanding > 0) {
            uint256 stakedBal = proxy.balanceOf(gauge);
            proxy.withdraw(
                gauge,
                address(want),
                Math.min(stakedBal, _debtOutstanding)
            );

            _debtPayment = Math.min(_debtOutstanding, balanceOfWant());
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _toInvest = balanceOfWant();
        want.safeTransfer(address(proxy), _toInvest);
        proxy.deposit(gauge, address(want));
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 wantBal = balanceOfWant();
        uint256 stakedBal = proxy.balanceOf(gauge);

        if (_amountNeeded > wantBal) {
            proxy.withdraw(
                gauge,
                address(want),
                Math.min(stakedBal, _amountNeeded - wantBal)
            );
            
            _liquidatedAmount = balanceOfWant().sub(wantBal);
            
            if(_liquidatedAmount < _amountNeeded){
                _loss = _amountNeeded.sub(_liquidatedAmount);
            }
        }
        
        require(_liquidatedAmount + _loss == _amountNeeded);
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 gaugeTokens = proxy.balanceOf(gauge);
        if (gaugeTokens > 0) {
            proxy.withdraw(gauge, address(want), gaugeTokens);
        }
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = gauge;
        protected[1] = address(crv);

        return protected;
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        return proxy.balanceOf(gauge);
    }

    //
    // setters
    //
    function switchDex(bool isUniswap) external onlyAuthorized {
        dex = isUniswap ? uniswapRouter : sushiswapRouter;
    }

    function setProxy(address _proxy) external onlyGovernance {
        proxy = StrategyProxy(_proxy);
    }

    function setKeepCRV(uint256 _keepCRV) external onlyGovernance {
        keepCRV = _keepCRV;
    }

    // enable ability to recieve ETH
    receive() external payable {}
}
