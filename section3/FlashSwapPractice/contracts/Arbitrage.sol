// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import { ArbitragePracticeTest } from "../test/ArbitragePractice.sol";
import { IUniswapV2Router01 } from "v2-periphery/interfaces/IUniswapV2Router01.sol";

// This is a pracitce contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    struct CallbackData {
        address borrowPool;
        address targetSwapPool;
        address borrowToken;
        address debtToken;
        uint256 borrowAmount;
        uint256 debtAmount;
        uint256 debtAmountOut;
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(sender == address(this), "Sender must be this contract");
        require(amount0 > 0 || amount1 > 0, "amount0 or amount1 must be greater than 0");

        // 3. decode callback data
        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        // 4. swap WETH to USDC
        IERC20(callbackData.borrowToken).transfer(callbackData.targetSwapPool, callbackData.borrowAmount);
        IUniswapV2Pair(callbackData.targetSwapPool).swap(0, callbackData.debtAmountOut, address(this), "");
        // 5. repay USDC to lower price pool
        IERC20(callbackData.debtToken).transfer(callbackData.borrowPool, callbackData.debtAmount);
    }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // 1. finish callbackData

        address weth9 = IUniswapV2Pair(priceLowerPool).token0();
        address usdc = IUniswapV2Pair(priceLowerPool).token1();
        // token0 weth
        // token1 usdc
        ArbitragePracticeTest pt = ArbitragePracticeTest(msg.sender);

        IUniswapV2Router01 uniswapV2Router = pt.uniswapV2Router();

        address[] memory borrowPath = new address[](2);
        borrowPath[0] = usdc;
        borrowPath[1] = weth9;
        uint256 debtAmount = uniswapV2Router.getAmountsIn(borrowETH, borrowPath)[0];
        //445 781790
        IUniswapV2Router01 sushiSwapV2Router = pt.sushiSwapV2Router();
        address[] memory debtPath = new address[](2);
        debtPath[0] = weth9;
        debtPath[1] = usdc;
        uint256 debtAmountOut = sushiSwapV2Router.getAmountsOut(borrowETH, debtPath)[1];
        //543 966536
        CallbackData memory callbackData;
        callbackData.borrowPool = priceLowerPool;
        callbackData.targetSwapPool = priceHigherPool;
        callbackData.borrowToken = IUniswapV2Pair(priceLowerPool).token0(); // WETH9
        callbackData.debtToken = IUniswapV2Pair(priceLowerPool).token1(); // USDC
        callbackData.borrowAmount = borrowETH;
        callbackData.debtAmount = debtAmount;
        callbackData.debtAmountOut = debtAmountOut;

        // 2. flash swap (borrow WETH from lower price pool)

        // Uncomment next line when you do the homework
        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(callbackData));
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
