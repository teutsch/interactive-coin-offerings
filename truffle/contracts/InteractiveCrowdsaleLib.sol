pragma solidity ^0.4.18;

/**
 * @title InteractiveCrowdsaleLib
 * @author Majoolr.io
 *
 * version 1.0.0
 * Copyright (c) 2017 Majoolr, LLC
 * The MIT License (MIT)
 * https://github.com/Majoolr/ethereum-libraries/blob/master/LICENSE
 *
 * The InteractiveCrowdsale Library provides functionality to create a crowdsale
 * based on the white paper initially proposed by Jason Teutsch and Vitalik
 * Buterin. See https://people.cs.uchicago.edu/~teutsch/papers/ico.pdf for
 * further information.
 *
 * This library was developed in a collaborative effort among many organizations
 * including TrueBit, Majoolr, Zeppelin, and Consensys.
 * For further information: truebit.io, majoolr.io, zeppelin.solutions,
 * consensys.net
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import "./BasicMathLib.sol";
import "./TokenLib.sol";
import "./CrowdsaleToken.sol";
import "./CrowdsaleLib.sol";
import "./LinkedListLib.sol";

library InteractiveCrowdsaleLib {
  using BasicMathLib for uint256;
  using TokenLib for TokenLib.TokenStorage;
  using LinkedListLib for LinkedListLib.LinkedList;
  using CrowdsaleLib for CrowdsaleLib.CrowdsaleStorage;

  uint256 constant NULL = 0;
  uint256 constant HEAD = 0;
  bool constant PREV = false;
  bool constant NEXT = true;

  struct InteractiveCrowdsaleStorage {

    CrowdsaleLib.CrowdsaleStorage base; // base storage from CrowdsaleLib

    // List of personal valuations, sorted from smallest to largest (from LinkedListLib)
    LinkedListLib.LinkedList valuationsList;

    // Info holder for token creation
    TokenLib.TokenStorage tokenInfo;

    uint256 endWithdrawalTime;   // time when manual withdrawals are no longer allowed

    // current total valuation of the sale
    // actual amount of ETH committed, taking into account partial purchases
    uint256 totalValuation;

    // amount of value committed at this valuation, cannot rely on owner balance
    // due to fluctations in commitment calculations needed after owner withdraws
    // the amount of ETH committed, including total bids that will eventually get partial purchases
    uint256 valueCommitted;

    // the bucket that sits either at or just below current total valuation
    uint256 currentBucket;

    // minimim amount that the sale needs to make to be successfull
    uint256 minimumRaise;

    // percentage of total tokens being sold in this sale
    uint8 percentBeingSold;

    // the bonus amount for early bidders
    uint256 priceBonusPercent;

    bool ownerHasWithdrawnETH;

    // shows the price that the address purchased tokens at
    mapping (address => uint256) pricePurchasedAt;

    // the sums of bids at each valuation
    mapping (uint256 => uint256) valuationSums;

    // the number of active bids at a certain valuation cap
    mapping (uint256 => uint256) numBidsAtValuation;

    // the valuation cap that each address has submitted
    mapping (address => uint256) personalCaps;
  }

  // Indicates when a bidder submits a bid to the crowdsale
  event LogBidAccepted(address indexed bidder, uint256 amount, uint256 personalValuation);

  // Indicates when a bidder manually withdraws their bid from the crowdsale
  event LogBidWithdrawn(address indexed bidder, uint256 amount, uint256 personalValuation);

  // Indicates when a bid is removed by the automated bid removal process
  event LogBidRemoved(address indexed bidder, uint256 personalValuation);

  // Generic Error Msg Event
  event LogErrorMsg(uint256 amount, string Msg);

  // Indicates when the price of the token changes
  event LogTokenPriceChange(uint256 amount, string Msg);

  // Logs the current bucket that the valuation points to, the total valuation of the sale, and the amount of ETH committed, including total bids that will eventually get partial purchases
  event BucketAndValuationAndCommitted(uint256 bucket, uint256 valuation, uint256 committed);

  /// @dev Called by a crowdsale contract upon creation.
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _owner Address of crowdsale owner
  /// @param _saleData Array of 3 item arrays such that, in each 3 element
  /// array index-0 is timestamp, index-1 is price in cents at that time
  /// index-2 is address purchase valuation at that time, 0 if no address valuation
  /// @param _endTime Timestamp of sale end time
  function init(InteractiveCrowdsaleStorage storage self,
                address _owner,
                uint256[] _saleData,
                uint256 _priceBonusPercent,
                uint256 _minimumRaise,
                uint256 _endWithdrawalTime,
                uint256 _endTime,
                uint8 _percentBeingSold,
                string _tokenName,
                string _tokenSymbol,
                uint8 _tokenDecimals,
                bool _allowMinting) public
  {
    self.base.init(_owner,
                _saleData,
                _endTime,
                0, // no token burning for iico
                CrowdsaleToken(0)); // no tokens created prior to iico

    require(_endWithdrawalTime < _endTime);
    require(_minimumRaise > 0);
    require(_percentBeingSold > 0);
    require(_priceBonusPercent > 0);

    self.minimumRaise = _minimumRaise;
    self.endWithdrawalTime = _endWithdrawalTime;
    self.percentBeingSold = _percentBeingSold;
    self.priceBonusPercent = _priceBonusPercent;

    self.tokenInfo.name = _tokenName;
    self.tokenInfo.symbol = _tokenSymbol;
    self.tokenInfo.decimals = _tokenDecimals;
    self.tokenInfo.stillMinting = _allowMinting;
  }

  /// @dev calculates the number of digits in a given number
  /// @param _number the number for which we're caluclating digits
  /// @return _digits the number of digits in _number
  function numDigits(uint256 _number) public pure returns (uint256) {
    uint256 _digits = 0;
    while (_number != 0) {
      _number /= 10;
      _digits++;
    }
    return _digits;
  }

  /// @dev calculates the number of tokens purchased based on the amount of wei
  ///      spent and the price of tokens
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _amount amound of wei that the buyer sent
  /// @param _price price of tokens in the sale, in tokens/ETH
  /// @return uint256 numTokens the number of tokens purchased
  /// @return remainder  any remaining wei leftover from integer division
  function calculateTokenPurchase(InteractiveCrowdsaleStorage storage self,
                                  uint256 _amount,
                                  uint256 _price)
                                  internal
                                  view
                                  returns (uint256,uint256)
  {
    uint256 remainder = 0; //temp calc holder for division remainder for leftover wei

    bool err;
    uint256 numTokens;
    uint256 weiTokens; //temp calc holder

    // Find the number of tokens as a function in wei
    (err,weiTokens) = _amount.times(_price);
    require(!err);

    numTokens = weiTokens / 1000000000000000000;
    remainder = weiTokens % 1000000000000000000;
    remainder = remainder / _price;

    // make sure there are enough tokens available to satisfy the bid
    assert(numTokens <= self.base.token.balanceOf(this));

    return (numTokens,remainder);
  }

  function getCurrentBonus(InteractiveCrowdsaleStorage storage self) internal returns (uint256){
    uint256 bonusTime = self.endWithdrawalTime - self.base.startTime;
    uint256 elapsed = now - self.base.startTime;
    uint256 percentElapsed = (elapsed * 100)/bonusTime;

    uint256 currentBonus = self.priceBonusPercent - ((percentElapsed * self.priceBonusPercent)/100);
  }

  /// @dev Called when an address wants to submit bid to the sale
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _amount amound of wei that the buyer is sending
  /// @param _personalCap the total crowdsale valuation (wei) that the bidder is comfortable with
  /// @param _valuePredict prediction of where the valuation will go in the linked list
  /// @return true on succesful bid
  function submitBid(InteractiveCrowdsaleStorage storage self,
                      uint256 _amount,
                      uint256 _personalCap,
                      uint256 _valuePredict) public returns (bool)
  {
    require(msg.sender != self.base.owner);
    require(self.base.validPurchase());
    // bidder can't have already bid
    require(self.personalCaps[msg.sender] == 0 && self.base.hasContributed[msg.sender] == 0);

    uint256 _bonusPercent;
    if (now < self.endWithdrawalTime) {
      require(_personalCap > _amount);
      _bonusPercent = getCurrentBonus(self);
    } else {
      // The personal valuation submitted must be greater than the current
      // valuation plus the bid
      require(_personalCap >= self.totalValuation + _amount);
    }

    // personal valuation and minimum should be set to the proper granularity,
    // only three most significant values can be non-zero
    uint256 digits = numDigits(_personalCap);
    if(digits > 3)
      require((_personalCap % (10**(digits - 3))) == 0);

    // add the bid to the sorted valuations list
    uint256 _listSpot;
    if(!self.valuationsList.nodeExists(_personalCap)){
        _listSpot = self.valuationsList.getSortedSpot(_valuePredict,_personalCap,NEXT);
        self.valuationsList.insert(_listSpot,_personalCap,PREV);
    }

    // add the bid to the address => cap mapping
    self.personalCaps[msg.sender] = _personalCap;

    // add the bid to the sum of bids at this valuation
    self.valuationSums[_personalCap] += _amount;
    self.numBidsAtValuation[_personalCap] += 1;

    // add the bid to bidder's contribution amount.  can't overflow because it
    // is under the cap
    self.base.hasContributed[msg.sender] += _amount;

    // temp variables for calculation
    uint256 _proposedCommit;
    uint256 _currentBucket;
    bool loop;
    bool exists;

    // we only affect the pointer if we are coming in above it
    if(_personalCap > self.currentBucket){

      // if our valuation is sitting at the current bucket then we are using
      // commitments right at their cap
      if (self.totalValuation == self.currentBucket) {
        // we are going to drop those commitments to see if we are going to be
        // greater than the current bucket without them
        _proposedCommit = (self.valueCommitted - self.valuationSums[self.currentBucket]) + _amount;
        if(_proposedCommit > self.currentBucket){ loop = true; }
      } else {
        // else we're sitting in between buckets and have already dropped the
        // previous commitments
        _proposedCommit = self.totalValuation + _amount;
        loop = true;
      }

      if(loop){
        // if we're going to loop we move to the next bucket
        (exists,_currentBucket) = self.valuationsList.getAdjacent(self.currentBucket, NEXT);

        while(_proposedCommit >= _currentBucket){
          // while we are proposed higher than the next bucket we drop commitments
          // and iterate to the next
          _proposedCommit = _proposedCommit - self.valuationSums[_currentBucket];
          (exists,_currentBucket) = self.valuationsList.getAdjacent(_currentBucket, NEXT);
        }
        // once we've reached a bucket too high we move back to the last bucket and set it
        (exists, _currentBucket) = self.valuationsList.getAdjacent(_currentBucket, PREV);
        self.currentBucket = _currentBucket;
      } else {
        // else we're staying at the current bucket
        _currentBucket = self.currentBucket;
      }
      // if our proposed commitment is less than or equal to the bucket
      if(_proposedCommit <= _currentBucket){
        // we add the commitments in that bucket
        _proposedCommit += self.valuationSums[_currentBucket];
        // and our value is capped at that bucket
        self.totalValuation = _currentBucket;
      } else {
        // else our total value is in between buckets and it equals the total commitements
        self.totalValuation = _proposedCommit;
      }

      self.valueCommitted = _proposedCommit;
    } else if(_personalCap == self.totalValuation){
      self.valueCommitted += _amount;
    }

    self.pricePurchasedAt[msg.sender] = (self.base.tokensPerEth * (100 + _bonusPercent))/100;
    LogBidAccepted(msg.sender, _amount, _personalCap);
    BucketAndValuationAndCommitted(self.currentBucket, self.totalValuation, self.valueCommitted);
    return true;
  }


  /// @dev Called when an address wants to manually withdraw their bid from the
  ///      sale. puts their wei in the LeftoverWei mapping
  /// @param self Stored crowdsale frowithdrawalm crowdsale contract
  /// @return true on succesful
  function withdrawBid(InteractiveCrowdsaleStorage storage self) public returns (bool) {
    // The sender has to have already bid on the sale
    require(self.personalCaps[msg.sender] > 0);

    uint256 refundWei;
    // cannot withdraw after compulsory withdraw period is over unless the bid's
    // valuation is below the cutoff
    if (now >= self.endWithdrawalTime) {
      require(self.personalCaps[msg.sender] < self.totalValuation);

      refundWei = self.base.hasContributed[msg.sender];

    } else {
      //uint256 multiplierPercent = (100*((self.endWithdrawalTime+self.base.milestoneTimes[0]) - now))/self.endWithdrawalTime;
      //refundWei = (multiplierPercent*self.base.hasContributed[msg.sender])/100;
      refundWei = self.base.hasContributed[msg.sender];
    }

    // Put the sender's contributed wei into the leftoverWei mapping for later withdrawal
    self.base.leftoverWei[msg.sender] += refundWei;

    // subtract the bidder's refund from its total contribution
    self.base.hasContributed[msg.sender] -= refundWei;

    // subtract the bid from the sum of bids at this valuation
    self.valuationSums[self.personalCaps[msg.sender]] -= refundWei;
    self.numBidsAtValuation[self.personalCaps[msg.sender]] -= 1;

    uint256 _proposedCommit;
    uint256 _proposedValue;
    uint256 _currentBucket;
    bool loop;
    bool exists;

    // bidder's withdrawal only affects the pointer if the personal cap is at or
    // above the current valuation
    if(self.personalCaps[msg.sender] >= self.totalValuation){

      // first we remove the refundWei from the committed value
      _proposedCommit = self.valueCommitted - refundWei;

      // if we've dropped below the current bucket
      if(_proposedCommit <= self.currentBucket){
        // and current valuation is above the bucket
        if(self.totalValuation > self.currentBucket){
          _proposedCommit += self.valuationSums[self.currentBucket];
        }

        if(_proposedCommit >= self.currentBucket){
          _proposedValue = self.currentBucket;
        } else {
          // if we are still below the current bucket then we need to iterate
          loop = true;
        }
      } else {
        if(self.totalValuation == self.currentBucket){
          _proposedValue = self.totalValuation;
        } else {
          _proposedValue = _proposedCommit;
        }
      }


      if(loop){
        // if we're going to loop we move to the previous bucket
        (exists,_currentBucket) = self.valuationsList.getAdjacent(self.currentBucket, PREV);
        while(_proposedCommit <= _currentBucket){
          // while we are proposed lower than the previous bucket we add commitments
          _proposedCommit += self.valuationSums[_currentBucket];
          // and iterate to the previous
          if(_proposedCommit >= _currentBucket){
            _proposedValue = _currentBucket;
          } else {
            (exists,_currentBucket) = self.valuationsList.getAdjacent(_currentBucket, PREV);
          }
        }

        if(_proposedValue == 0) { _proposedValue = _proposedCommit; }

        self.currentBucket = _currentBucket;
      }

      self.totalValuation = _proposedValue;
      self.valueCommitted = _proposedCommit;
    }

    LogBidWithdrawn(msg.sender, self.base.hasContributed[msg.sender], self.personalCaps[msg.sender]);
    return true;
    BucketAndValuationAndCommitted(self.currentBucket, self.totalValuation, self.valueCommitted);
  }

  /// @dev This should be called once the sale is over to commit all bids into
  ///      the owner's bucket.
  function finalizeSale(InteractiveCrowdsaleStorage storage self) public returns (bool) {
    require(now >= self.base.endTime);
    require(!self.ownerHasWithdrawnETH);

    require(launchToken(self));

    self.ownerHasWithdrawnETH = true;
    self.base.ownerBalance = self.valueCommitted;
  }

  /// @dev Mints the token being sold by taking the percentage of the token supply
  ///      being sold in this sale along with the valuation, derives all necessary
  ///      values and then transfers owner tokens to the owner.
  function launchToken(InteractiveCrowdsaleStorage storage self) internal returns (bool) {

    uint256 _fullValue = (self.totalValuation*100)/uint256(self.percentBeingSold);
    uint256 _bonusValue = (_fullValue * (100 + self.priceBonusPercent))/100;
    uint256 _supply = (_fullValue * self.base.tokensPerEth) * (10**uint256(self.tokenInfo.decimals));
    uint256 _bonusTokens = (_bonusValue * self.base.tokensPerEth) * (10**uint256(self.tokenInfo.decimals));
    uint256 _ownerTokens = _supply - ((_supply * uint256(self.percentBeingSold))/100);
    uint256 _totalSupply = _supply + _bonusTokens;

    self.base.token = new CrowdsaleToken(address(this),
                                         self.tokenInfo.name,
                                         self.tokenInfo.symbol,
                                         self.tokenInfo.decimals,
                                         _totalSupply,
                                         self.tokenInfo.stillMinting);

    if(saleCanceled(self)){
      self.base.token.transfer(self.base.owner, _supply);
      self.base.token.burnToken(_bonusTokens);
    } else {
      self.base.token.transfer(self.base.owner, _ownerTokens);
    }
    self.base.token.changeOwner(self.base.owner);
    self.base.startingTokenBalance = _supply - _ownerTokens;

    return true;
  }

  function saleCanceled(InteractiveCrowdsaleStorage storage self) internal view returns(bool canceled){
    canceled = (self.totalValuation < self.minimumRaise) ||
               ((now > (self.base.endTime + 30 days)) && !self.ownerHasWithdrawnETH);
  }

  /// @dev If the address' personal cap is below the pointer, refund them all their ETH.
  ///      if it is above the pointer, calculate tokens purchased and refund leftoever ETH
  /// @param self Stored crowdsale from crowdsale contract
  /// @return bool success if the contract runs successfully
  function retreiveFinalResult(InteractiveCrowdsaleStorage storage self) internal returns (bool) {
    require(now > self.base.endTime);
    require(self.base.hasContributed[msg.sender] > 0);
    require(self.ownerHasWithdrawnETH);

    uint256 numTokens;
    uint256 remainder;
    bool err;

    if (saleCanceled(self)) {
      self.base.leftoverWei[msg.sender] += self.base.hasContributed[msg.sender];
      return true;
    }

    if (self.personalCaps[msg.sender] < self.totalValuation) {

      self.base.leftoverWei[msg.sender] += self.base.hasContributed[msg.sender];
      return true;

    } else if (self.personalCaps[msg.sender] == self.totalValuation) {
      uint256 q;

      // calculate the fraction of each minimal valuation bidders ether and tokens to refund
      q = (100*(self.valueCommitted - self.totalValuation)/(self.valuationSums[self.totalValuation])) + 1;

      // calculate the portion that this address has to take out of their bid
      uint256 refundAmount = (q*self.base.hasContributed[msg.sender])/100;

      // refund that amount of wei to the address
      self.base.leftoverWei[msg.sender] += refundAmount;

      // subtract that amount the address' contribution
      self.base.hasContributed[msg.sender] -= refundAmount;
    }

    // calculate the number of tokens that the bidder purchased
    (numTokens, remainder) = calculateTokenPurchase(self,self.base.hasContributed[msg.sender],self.pricePurchasedAt[msg.sender]);

    // add tokens to the bidders purchase.  can't overflow because it will be under the cap
    self.base.withdrawTokensMap[msg.sender] += numTokens;
    self.valueCommitted = self.valueCommitted - remainder;
    self.base.leftoverWei[msg.sender] += remainder;

    // burn any extra bonus tokens
    if(self.pricePurchasedAt[msg.sender] > self.base.tokensPerEth){
      uint256 _fullBonus;
      uint256 _fullBonusPrice = (self.base.tokensPerEth*(100 + self.priceBonusPercent))/100;
      (_fullBonus, remainder) = calculateTokenPurchase(self, self.base.hasContributed[msg.sender], _fullBonusPrice);
      uint256 _leftoverBonus = _fullBonus - numTokens;
      self.base.token.burnToken(_leftoverBonus);
    }

    return true;
  }



   /*Functions "inherited" from CrowdsaleLib library*/

  function withdrawTokens(InteractiveCrowdsaleStorage storage self) internal returns (bool) {
    require(now > self.base.endTime);

    retreiveFinalResult(self);

    return self.base.withdrawTokens();
  }

  function withdrawLeftoverWei(InteractiveCrowdsaleStorage storage self) internal returns (bool) {
    if (now > self.base.endTime) {
      retreiveFinalResult(self);
    }

    return self.base.withdrawLeftoverWei();
  }

  function withdrawOwnerEth(InteractiveCrowdsaleStorage storage self) internal returns (bool) {

    return self.base.withdrawOwnerEth();
  }

  function crowdsaleActive(InteractiveCrowdsaleStorage storage self) internal view returns (bool) {
    return self.base.crowdsaleActive();
  }

  function crowdsaleEnded(InteractiveCrowdsaleStorage storage self) internal view returns (bool) {
    return self.base.crowdsaleEnded();
  }

  function getPersonalCap(InteractiveCrowdsaleStorage storage self, address _bidder) internal view returns (uint256) {
    return self.personalCaps[_bidder];
  }

  function getSaleData(InteractiveCrowdsaleStorage storage self, uint256 _timestamp) internal view returns (uint256[3]) {
    return self.base.getSaleData(_timestamp);
  }

  function getTokensSold(InteractiveCrowdsaleStorage storage self) internal view returns (uint256) {
    return self.base.getTokensSold();
  }

}
