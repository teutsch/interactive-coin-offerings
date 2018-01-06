pragma solidity ^0.4.15;

/****************
*
*  Test contract for tesing libraries on networks
*
*****************/

import "./InteractiveCrowdsaleLib.sol";
import "./CrowdsaleToken.sol";

contract InteractiveCrowdsaleTestContract {
  using InteractiveCrowdsaleLib for InteractiveCrowdsaleLib.InteractiveCrowdsaleStorage;

  InteractiveCrowdsaleLib.InteractiveCrowdsaleStorage sale;

  event LogErrorMsg(uint256 amount, string Msg);

  function InteractiveCrowdsaleTestContract(
    address owner,
    uint256[] saleData,
    uint256 priceBonusPercent,
    uint256 minimumRaise,
    uint256 endWithdrawalTime,
    uint256 endTime,
    uint8 percentBeingSold,
    string tokenName,
    string tokenSymbol,
    uint8 tokenDecimals,
    bool allowMinting) public
  {
  	sale.init(owner,
              saleData,
              priceBonusPercent,
              minimumRaise,
              endWithdrawalTime,
              endTime,
              percentBeingSold,
              tokenName,
              tokenSymbol,
              tokenDecimals,
              allowMinting);
  }

  function () public {
    LogErrorMsg(0, 'Did not send correct data!');
  }

  function submitBid(uint256 _personalValuation, uint256 _listPredict) payable public returns (bool) {
    return sale.submitBid(msg.value, _personalValuation, _listPredict);
  }

  function withdrawBid() public returns (bool) {
    return sale.withdrawBid();
  }

  function withdrawTokens() public returns (bool) {
    return sale.withdrawTokens();
  }

  function withdrawLeftoverWei() public returns (bool) {
    return sale.withdrawLeftoverWei();
  }

  function withdrawOwnerEth() public returns (bool) {
  	return sale.withdrawOwnerEth();
  }

  function crowdsaleActive() public view returns (bool) {
  	return sale.crowdsaleActive();
  }

  function crowdsaleEnded() public view returns (bool) {
  	return sale.crowdsaleEnded();
  }

  function getOwner() public view returns (address) {
    return sale.base.owner;
  }

  function getTokensPerEth() public view returns (uint256) {
    return sale.base.tokensPerEth;
  }

  function getStartTime() public view returns (uint256) {
    return sale.base.startTime;
  }

  function getEndTime() public view returns (uint256) {
    return sale.base.endTime;
  }

  function getMinimumRaise() public view returns (uint256) {
    return sale.minimumRaise;
  }

  function getEndWithdrawlTime() public view returns (uint256) {
    return sale.endWithdrawalTime;
  }

  function getCommittedCapital() public view returns (uint256) {
    return sale.valueCommitted;
  }

  function getContribution(address _buyer) public view returns (uint256) {
    return sale.base.hasContributed[_buyer];
  }

  function getTokenPurchase(address _buyer) public view returns (uint256) {
    return sale.base.withdrawTokensMap[_buyer];
  }

  function getLeftoverWei(address _buyer) public view returns (uint256) {
    return sale.base.leftoverWei[_buyer];
  }

  function getPersonalCap(address _bidder) public view returns (uint256) {
    return sale.getPersonalCap(_bidder);
  }

  function getSaleData(uint256 timestamp) public view returns (uint256[3]) {
    return sale.getSaleData(timestamp);
  }

  function getTokensSold() public view returns (uint256) {
    return sale.getTokensSold();
  }

  function getPercentBeingSold() public view returns (uint256) {
    return sale.percentBeingSold;
  }

  function getCurrentBucket() public view returns (uint256) {
    return sale.currentBucket;
  }

  function getTotalValuation() public view returns (uint256) {
    return sale.totalValuation;
  }
}
