// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author SAHIL
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////////////
    // ERRORS        ///
    ///////////////////////

    error DSCEngine_NeedsMoreThanZero();
    error DSCEngine_tokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_NotAllowedToken();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();

    /////////////////////////
    // State Varaibles         ///
    ///////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateralization ratio
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means a 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited; // userCollateralDeposits
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    /////////////////////////
    // Events        ///
    ///////////////////////

    event CollateralDeposited(
        address indexed user,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    /////////////////////////
    // MODIFIERS         ///
    ///////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine_NotAllowedToken();
        }
        _;
    }

    /////////////////////////
    // Functions         ///
    ///////////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_tokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////
    // External functions         ///
    ///////////////////////

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @notice follows CEI
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom( // transferFrom(from, to, amount) is a standard ERC20 function.
            msg.sender,
            address(this),
            amountCollateral
        );

        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    /*
     * @param tokenCollateralAddress The collateral address to redeem
     *@param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transaction
     */

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);

        //redeemCollateral already checks health factor, so we dont need to check it again here
        // we need to burn the DSC first, because if we try to redeem collateral first, it will break the health factor
    }

    // $100 ETH - > $40ETH
    // $50 DSC                        ( undercollateralized)
    // $100 ETH -> $60 ETH
    // $50 DSc                        ( close to being undercollaterized so gets liquidated rn)

    // so what we can do is we cam set a threshold to lets say 150% , means if u have $50 in the system , u need to have at least 75ETH at all times , with this there is a little bit of a buffer that way we can never be under collaterized
    // $100 ETH -> $74 ETH  ,   lets say our threshold was 75 and it went to $74 ETH now we can liquidate and we can say " Hey , if someone , pays back your borrow , your minted DSC , they can have all your collateral for a discount"
    // $50 DSC                  // continue of upper line -> maybe we say : hey, somebody pay back this 50 DSC and they can have this $74 worth of ETH , somebody is going to be very incentivized to do this because they are going to make $24 profit
    // now the one who paid $50 DSC , they get all your collateral and u lose the collateral , and all they had to do was pay $50 of DSc to get $74 worth of ETH , so $24 profit.

    // in order to redeem collateral:
    //1. health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // lets say i put $100 in and then i mint , lets say $20 versus the DSC , lets say now i want to burn all my DSC and i want to withdraw all of my ETH . well, if i try to redeem all my ETH, it will break ,  right?  it will break my health factor
    // so we need to do first is I need to first burn back my DSC and then I need i need to redeem my ETH

    //$100 ETH -> $20 DSC
    //100(break)
    //1. burn DSC
    //2. redeem ETH

    /*
        * @motice follows CEI
        *@param amountDscToMint The amount of decentralized stablecoin to mint
        @notice they must have more collateral value than minimum threshold
        */

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        // 1. check if the user has enough collateral               (collateral vlaue > dsc)
        // 2. check if the user has enough collateral to mint DSC
        // 3. mint DSC to the user
        // 4. emit an event
        // 5. transfer the collateral to the contract

        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        // s_DSCMinted[msg.sender] -= amount;

        // bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        // if (!success) {
        //     revert DSCEngine_TransferFailed();
        // }
        // i_dsc.burn(amount);

        // burning is highly unlikely to break health factor, so we dont need to check it but still
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // If we do start nearing underCollateralization , we need someone to liquidate positions

    // lets say $100ETH backing $50DSC
    //  and somehow now$20ETH backs up $50DSC <- DSC isnt worth $1anymore
    // we need to make sure we liquidate people's positions

    //$75 backing $50 DSC
    // Liquidator take $75 backing and burns off the $50 DSC
    // liquidator gets $25 profit

    // if someone is almost underCollateralized , we will pay you to liquidate them

    /*
     * @param collateral the ERC20 collateral address to liquidate from the user
     * @param user the user who has broken the health factor ,their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be rouighly 200% overcollaterized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized , then we wouldn't be able to incentive the liquidators
     * for example , if the price of the collateral plummeted before anyone could be liquidated.
     */

    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        //need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine_HealthFactorOk();
        }

        // and give them a
        // we want to burn their DSc "debt"  and take thier collateral
        // BAD USER : lets say they have $140ETH , $100 DSC . with this they surely have a health factor below 1
        // debtToCover = $100
        //  now we are gonna payback $100 of DSC  == ?? ETH
        // 0.05 ETH

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // and give them a 10% bonus
        // so we are giving the liquidator $110 of WETH for 100DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        //and sweep extra amounts into a treasury
        // 0.05 ETH *.1 = 0.005 , -> bonus collateral
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        ); // -> user is the one being liquidated, msg.sender is the one calling liquidae ,
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }
    }

    /////////////////////////
    // Private & internal functions         ///     _ with a function name is used just to indicate that it is a private or internal function
    ///////////////////////

    /* @dev Low-level internal function , do not call unless the function calling it is checking for health factors being broken
     *
     *
     */
    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        //-> onbehalf here is ki kiska debt we are paying
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        // the conditional is hypothetically unreacahbale
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * reeturns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSc minted
        // total collateral value

        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);

        if (totalDscMinted == 0) return type(uint256).max;

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;

        //1000ETH *50 = 50,000 / 100 = 500
        // $150 ETH / 100 DSC = 1.5
        // 150*50 = 7500 / 100 = (75/100) < 1
        // return (collateralValueInUsd / totalDscMinted); // ()

        // 1000ETH / 100DSC
        // 1000*50 = 50000 / 100 = (500/100)>1
    }

    // 1. Check health factor ( do they have enough collatera)
    //2. Revert if they dont

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////
    // Public and External View functions         ///
    ///////////////////////

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each colateral token, get the amount they have deposited, and map it to the price to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        // → You pass a token address and an amount of that token → It returns: How much that token is worth in USD
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // lets say 1ETH = $1000
        // returned value from CL will be 1000 * 1e8
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; //(1000 * 1e8 * (1e10)) * 1000 * 1e18;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
