//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    /*
    * @title DecentralizedStableCoin 
    * @author Malik the Amsterdamse
    * Collateral Exogenous (BTC/ETH)
    * Pegged to USD, helped by the burn function to maintain the price
    * Governs the DecentralizedStableCoinEngine
    * extend this on a later stage
    * value of all collateral should be <= $ backed value of DSC
    */

    /////////////////
    //// Error //////
    /////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressNeedsSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////
    //// State Variables/Mappings ////
    //////////////////////

    //used for math of the wei and eth numbers in getting pricefeed not to be a bloated wei number

    //price gets back as 8 decimals so verting to wei
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    // used to accurate reduce the amount of figures
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // means 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus to incentivized liquidation
    mapping(address token => address priceFeed) private s_priceFeeds;
    //track how much someone has deposited and of which token
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscToMint) s_DSCMinted;
    DecentralizedStableCoin private immutable i_dsc;
    address[] private s_collateralTokens;
    //s_tokenAllowed;

    /////////////////
    //// Events ////
    /////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    //amount is changed after redeemcollateral internal function is created (why?)
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    /////////////////
    //// Modifier ////
    /////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address Token) {
        if (s_priceFeeds[Token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////////////////////
    //// External Functions ////
    /////////////////////////////

    //pricefeeds are different on address per network so parsed in the constructor
    constructor(address[] memory tokenAddressess, address[] memory priceFeedAddresses, address dscAddress) {
        //sanity check to see if the lists are different then there is something wrong
        if (tokenAddressess.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressNeedsSameLength();
        }
        // loop through the addresses array, populate the pricefeeds with at every index the tokenAddress and its corresponding pricefeed address
        for (uint256 i = 0; i < tokenAddressess.length; i++) {
            s_priceFeeds[tokenAddressess[i]] = priceFeedAddresses[i];
            //get an array with all token addresses of the user
            s_collateralTokens.push(tokenAddressess[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }
    /////////////////
    //// External Functions ////
    /////////////////

    //takes the tokenaddress to deposit as collateral, the amount of collateral and dsc to be minted
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        //combines depositCollateral and mintDSC, deposits and mints in one transaction
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //pick the collateral type and how much to deposit, can someone just deposit collateral and mint later?

        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        //state is updated so there is an emit
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        //collateral is wrapped as IERC20 therefore it is imported from openzeppelin with transferfrom returns boolean
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        /* follows CEI, keeps track of how much is minted
        * after deposited collateral then mint
        * involving pricefeed, checking values 
        * collateral > dsc value 
        * taking in the amount they want to mint
        * collateral must be more than minimum threshold
        * one can not mint 0 Dsc
        */
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        //mint function returns a boolean, takes address to and an amount
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    //in order to redeem
    //choose which collateral
    //health factor above 1
    // if any code is repeated with the dont repeat yourself method cleaning up later
    // tokentransfer first then health
    //burn DSC so it is in one transaction
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        // _redeemCollateral(tokenCollateralAddress, amountCollateral, from, to);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // return the coin and get back collateral
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral); //checks healthFactor
    }

    // overcollateral coverage reduction by burning, gets called by redeem collateral
    function burnDsc(uint256 amountDsc) public moreThanZero(amountDsc) {
        _burnDsc(amountDsc, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //Patrick thinks it won't hit, because after there is less Dsc so the healthfactor should be better, question is if there would be a price drop in usd of the token and there are dsc tokens then maybe it could drop
    }

    // protect for undercollaterilization threshold, remove to save DSC, activate near collateralization
    // takes collateral address of the user that broke the health factor, debtTocover is amount of DSC tokens to improve
    // partial liquidation is possible, 200% overcollateralization, liquidators are incentivized.
    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // checking healthfactor, assign to variable, if ok, then stop
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //burn debt
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);
        //10% bonus to liquidator
        // feature if protocol is insolvent
        uint256 bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = bonusCollateral + tokenAmountFromDebtCovered;
        //give collateral, burn dsc
        _redeemCollateral(collateralToken, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        //revert if healthfactor did not improve
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        //also revert if liquidator is going to be having bad healthfactor ratio
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /////////////////////////////////////////////
    //// Private and Internal View Functions ////
    /////////////////////////////////////////////

    //underscore before the function name tells that it is an internal factor
    //ratio collateral to dsc function, need total dsc minted and collateral value in dollars

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_DSCMinted[user]; //what happens if the user has not minted anything but deposited???
        //get value in USD
        collateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }
    //there is a bug here according to Patrick

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256 healthFactor)
    {
        //require(totalDSCMinted > 0, "Total DSC minted must be greater than zero"); //is the bug solved with a division by zero prevention?

        if (totalDscMinted == 0) return type(uint256).max;
        // Return a default health factor value, 1? But I think can you call this info if the user is not in DSCMinted?
        // type(uint256).max; is used in the written example
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // checkHealthFactor;
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //special internal function as redeemcollateral is only accessible by the msg.sender
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //low level internal function, function calling it must check healthfactor is broken to call it
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        //first take Dsc back to our contract and then burn it
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }
    /////////////////////////////////////////////
    //// Public and External View Functions ////
    /////////////////////////////////////////////

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        // loop through each collateral token in the tokenarray, get amount deposited, map to price, get USD value return total
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            totalCollateralValueInUSD += getUsdValue(token, amount);
        }

        return totalCollateralValueInUSD;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        //uses chainlink, because they are simply the best in providing pricefeed data aggregated
        // first get the pricefeed of the token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        //get price of token, convert to dollar, usdAmountInWei/ Price in USD of the token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        (totalDSCMinted, collateralValueInUSD) = _getAccountInformation(user);
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

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }
}
