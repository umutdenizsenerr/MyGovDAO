const { expect } = require('chai');
const { ethers } = require('hardhat');

const {
  time,
  mine,
  loadFixture,
} = require('@nomicfoundation/hardhat-network-helpers');

const TOKEN_SUPPLY = '10000000';
let Token;
let owner;
let addr1;
let addr2;
let addr3;
let addr4;
let addr5;
let addr6;
let addr7;
let initial_contract_balance;
let initial_contract_token_balance;
let addresses;
describe('MyGov contract tests', function () {
  before(async function () {
    Token = await ethers.getContractFactory('MyGov');
    addresses = await ethers.getSigners();
    owner = addresses[0];
    addr1 = addresses[1];
    addr2 = addresses[2];
    addr3 = addresses[3];
    addr4 = addresses[4];
    addr5 = addresses[5];
    addr6 = addresses[6];
    addr7 = addresses[7];

    MyGovContract = await Token.connect(owner).deploy(TOKEN_SUPPLY);
  });

  this.beforeEach(async function () {
    initial_contract_balance = await ethers.provider.getBalance(
      MyGovContract.connect(owner).address
    );
    initial_contract_token_balance = await MyGovContract.connect(
      owner
    ).balanceOf(MyGovContract.connect(owner).address);
  });

  describe('Deployment', function () {
    it('Should assign the total supply of tokens to the contract', async function () {
      const contractBalance = await MyGovContract.connect(owner).balanceOf(
        MyGovContract.connect(owner).address
      );
      expect(await MyGovContract.totalSupply()).to.equal(contractBalance);
    });
  });

  describe('Faucet Test', function () {
    it('MyGov balance of the user should be one since faucet is used and "MyGov balance of the contract should be decreased by one since faucet is used', async function () {
      await MyGovContract.connect(owner).faucet();
      expect(
        await MyGovContract.connect(owner).balanceOf(owner.address)
      ).to.equal(1);
      expect(
        await MyGovContract.connect(owner).balanceOf(
          MyGovContract.connect(owner).address
        )
      ).to.equal(initial_contract_token_balance - 1);
    });
    it('User is not allowed to call faucet function more than once', async function () {
      await expect(MyGovContract.connect(owner).faucet()).to.be.revertedWith(
        'You have already used faucet'
      );
    });
  });

  describe('Donation Test', function () {
    it('Token balance of the user should decrease by one and token balance of the contract should increase by one', async function () {
      await MyGovContract.connect(owner).donateMyGovToken(1);
      expect(
        await MyGovContract.connect(owner).balanceOf(owner.address)
      ).to.equal(0);
      expect(
        (await MyGovContract.connect(owner).balanceOf(
          MyGovContract.connect(owner).address
        )) - 1
      ).to.equal(initial_contract_token_balance);
    });
    it('Token enough should be enough for given donation amount', async function () {
      await expect(
        MyGovContract.connect(addr1).donateMyGovToken(1)
      ).to.be.revertedWith('Not enough MyGov Token');
    });

    it('Ether balance of the contract should be increased by value of the message', async function () {
      await MyGovContract.connect(owner).donateEther({
        value: ethers.utils.parseEther('1'),
      });
      expect(
        await ethers.provider.getBalance(MyGovContract.connect(owner).address)
      ).to.equal(ethers.utils.parseEther('1').add(initial_contract_balance));
    });
  });

  describe('Submit Proposal Test', function () {
    it('Project proposal with id 1 should be submitted', async function () {
      await MyGovContract.connect(owner).customFaucet(7);
      let latest_contract_token_balance = await MyGovContract.connect(
        owner
      ).balanceOf(MyGovContract.connect(owner).address);
      await MyGovContract.connect(owner).submitProjectProposal(
        'QmRAQB6YaCyidP37UdDnjFY5vQuiBrcqdyoW1CuDgwxkD4',
        500 * 60 * 60 * 24,
        [1, 2, 3],
        [2, 9, 10],
        {
          value: ethers.utils.parseEther('0.1'),
        }
      );
      let project_id = await MyGovContract.connect(
        owner
      ).getNoOfProjectProposals();
      expect(1).to.equal(project_id);
      expect(latest_contract_token_balance).to.equal(
        (await MyGovContract.connect(owner).balanceOf(
          MyGovContract.connect(owner).address
        )) - 5
      );
      expect(
        await ethers.provider.getBalance(MyGovContract.connect(owner).address)
      ).to.equal(ethers.utils.parseEther('0.1').add(initial_contract_balance));
    });
    it('Project proposal with id 2 should be submitted', async function () {
      await MyGovContract.connect(owner).customFaucet(7);
      let latest_contract_token_balance = await MyGovContract.connect(
        owner
      ).balanceOf(MyGovContract.connect(owner).address);
      await MyGovContract.connect(owner).submitProjectProposal(
        'QmRAQB6YaCyidP37UdDnjFY5vQuiBrcqdyoW1CuDgwxkD5',
        500,
        [1, 2, 3],
        [2, 9, 10],
        {
          value: ethers.utils.parseEther('0.1'),
        }
      );
      let project_id = await MyGovContract.connect(
        owner
      ).getNoOfProjectProposals();
      expect(2).to.equal(project_id);
      expect(latest_contract_token_balance).to.equal(
        (await MyGovContract.connect(owner).balanceOf(
          MyGovContract.connect(owner).address
        )) - 5
      );
      expect(
        await ethers.provider.getBalance(MyGovContract.connect(owner).address)
      ).to.equal(ethers.utils.parseEther('0.1').add(initial_contract_balance));
    });
    it('Not enough Ether in message', async function () {
      await MyGovContract.connect(owner).customFaucet(7);
      await expect(
        MyGovContract.connect(owner).submitProjectProposal(
          'QmRAQB6YaCyidP37UdDnjFY5vQuiBrcqdyoW1CuDgwxkD6',
          500,
          [1, 2, 3],
          [2, 9, 10],
          {
            value: ethers.utils.parseEther('0.05'),
          }
        )
      ).to.be.revertedWith('You need to send exactly 0.1 ether');
    });
  });

  describe('Vote Test', function () {
    it('Project proposal with id 1 vote yes count should be increased by users vote weight', async function () {
      let initial_project = await MyGovContract.connect(owner).projects(1);
      let initial_vote_yes_count = await initial_project.vote_yes_count;

      await MyGovContract.connect(owner).voteForProjectProposal(1, true);

      let project = await MyGovContract.connect(owner).projects(1);

      expect(await project.vote_yes_count).to.equal(
        await initial_vote_yes_count.add(1)
      );
    });
    it('Project proposal with id 1 vote yes count should be increased by users vote weight', async function () {
      await expect(
        MyGovContract.connect(owner).voteForProjectProposal(1, true)
      ).to.be.revertedWith('User has already voted for this project');
    });
    it('User should be member to vote', async function () {
      await expect(
        MyGovContract.connect(addr1).voteForProjectProposal(1, true)
      ).to.be.revertedWith('User is not a member');
    });
  });

  describe('Delegate Vote Test', function () {
    it('User should be able to delegate his vote to another user and delegated users vote weight should be increased by sender users vote weight', async function () {
      await MyGovContract.connect(addr1).faucet();
      await MyGovContract.connect(addr2).faucet();
      let initial_project = await MyGovContract.connect(owner).projects(1);
      let initial_vote_yes_count = await initial_project.vote_yes_count;
      let sender_vote_weight = await MyGovContract.connect(addr1).getVoteWeight(
        addr1.address,
        1
      );
      let receiver_vote_weight = await MyGovContract.connect(
        addr2
      ).getVoteWeight(addr2.address, 1);
      await MyGovContract.connect(addr1).delegateVoteTo(addr2.address, 1);
      let new_receiver_vote_weight = await MyGovContract.connect(
        addr2
      ).getVoteWeight(addr2.address, 1);
      expect(new_receiver_vote_weight).to.equal(
        receiver_vote_weight.add(sender_vote_weight)
      );
    });
    it('User should be able to delegate his vote to already voted user and project vote count should automatically increased by senders vote weight since delegated user has already voted.', async function () {
      await MyGovContract.connect(addr3).faucet();
      let sender_vote_weight = await MyGovContract.connect(addr3).getVoteWeight(
        addr3.address,
        1
      );
      let initial_project = await MyGovContract.connect(owner).projects(1);
      let initial_vote_yes_count = await initial_project.vote_yes_count;

      await MyGovContract.connect(addr3).delegateVoteTo(owner.address, 1);

      let project = await MyGovContract.connect(owner).projects(1);

      expect(await project.vote_yes_count).to.equal(
        await initial_vote_yes_count.add(sender_vote_weight)
      );
    });
    it('Member cannot delegate to addres which is not a member', async function () {
      await expect(
        MyGovContract.connect(owner).delegateVoteTo(addr4.address, 1)
      ).to.be.revertedWith('Receiver is not a member');
    });
    it('User cannot delegate for this project because not a member', async function () {
      await expect(
        MyGovContract.connect(addr4).delegateVoteTo(owner.address, 1)
      ).to.be.revertedWith('Sender is not a member');
    });
    it('Member cannot delegate for this project because already voted', async function () {
      await MyGovContract.connect(addr4).faucet();
      await expect(
        MyGovContract.connect(owner).delegateVoteTo(addr4.address, 1)
      ).to.be.revertedWith('You have already voted for this project');
    });
    it('Member cannot delegate to itself', async function () {
      await expect(
        MyGovContract.connect(owner).delegateVoteTo(owner.address, 1)
      ).to.be.revertedWith('Self delegation is not allowed');
    });
  });

  describe('Vote For Project Payment Test', function () {
    it("Project 1's current payment should be voted and its vote count should be increased by one.", async function () {
      await MyGovContract.connect(addr5).faucet();

      let initial_current_payment_vote = await MyGovContract.connect(
        addr5
      ).getCurrentPaymentVote(1);
      await MyGovContract.connect(addr5).voteForProjectPayment(1, true);

      let new_current_payment_vote = await await MyGovContract.connect(
        addr5
      ).getCurrentPaymentVote(1);
      expect(await new_current_payment_vote).to.equal(
        await initial_current_payment_vote.add(1)
      );
    });
  });

  describe('Submit Survey Test', function () {
    it('Survey with id 1 should be submitted, Ether balance of the contract should be increased by 0.04 ether and MyGov Token balance of the contract should be increased by 2', async function () {
      await MyGovContract.connect(addr6).faucet();
      await MyGovContract.connect(addr6).customFaucet(6);
      let latest_contract_token_balance = await MyGovContract.connect(
        owner
      ).balanceOf(MyGovContract.connect(owner).address);
      await MyGovContract.connect(addr6).submitSurvey(
        'BsNLQmRAQB6YaCyidUdDnjFY5vQuiBrcqdyoWwxkD4',
        300,
        20,
        30,
        {
          value: ethers.utils.parseEther('0.04'),
        }
      );
      let survey_id = await MyGovContract.connect(addr6).survey_id_idx();
      expect(survey_id).to.equal(1);

      expect(latest_contract_token_balance).to.equal(
        (await MyGovContract.connect(owner).balanceOf(
          MyGovContract.connect(owner).address
        )) - 2
      );
      expect(
        await ethers.provider.getBalance(MyGovContract.connect(owner).address)
      ).to.equal(ethers.utils.parseEther('0.04').add(initial_contract_balance));
    });
    it('Not enough MyGov token in member address', async function () {
      await expect(
        MyGovContract.connect(addr2).submitSurvey(
          'BsNLQmRAQB6YaCyidUdDnjFY5vQuiBrcqdyoWwxkF5',
          300,
          20,
          30,
          {
            value: ethers.utils.parseEther('0.04'),
          }
        )
      ).to.be.revertedWith("User doesn't have enough MyGov token");
    });
    it('Not enough Ether in message', async function () {
      await MyGovContract.connect(addr6).customFaucet(6);
      await expect(
        MyGovContract.connect(addr3).submitSurvey(
          'BsNLQmRAQB6YaCyidUdDnjFY5vQuiBrcqdyoWwxkF5',
          300,
          20,
          30,
          {
            value: ethers.utils.parseEther('0.02'),
          }
        )
      ).to.be.revertedWith("User doesn't have enough MyGov token");
    });
  });

  describe('Take Survey Test', function () {
    it('User should take the survey with id 1', async function () {
      await MyGovContract.connect(addr7).faucet();
      await MyGovContract.connect(addr7).takeSurvey(1, [1, 0, 2]);

      let is_taken = await MyGovContract.connect(addr7).getTakenSurveys(
        addr7.address,
        1
      );
      expect(is_taken).to.equal(true);
    });
    it('Choice 0 value should be 1 in the survey with id 1', async function () {
      let num_taken,
        results = await MyGovContract.connect(addr7).getSurveyResults(1);
      expect(results[0]).to.equal(1);
    });
  });

  describe('Reserve Project Grant Test', function () {
    it('Only project owner should reserve payment for the project', async function () {
      await expect(
        MyGovContract.connect(addr1).reserveProjectGrant(1)
      ).to.be.revertedWith(
        'Only project owner can reserve payment for the project'
      );
    });
    it('Project should be funded to be reserved', async function () {
      expect(await MyGovContract.connect(owner).getIsProjectFunded(2)).equal(
        false
      );
      await expect(
        MyGovContract.connect(owner).reserveProjectGrant(2)
      ).to.be.revertedWith('Project is not funded, cannot reserve a grant');
    });
  });
  const multipleUserTest = async function (numberOfUsers) {
    let gasCost = {
      faucet: 0,
      customFaucet: 0,
      submitSurvey: 0,
      takeSurvey: 0,
      submitProjectProposal: 0,
      delegateVoteTo: 0,
      donateEther: 0,
      donateMyGovToken: 0,
      reserveProjectGrant: 0,
      voteForProjectPayment: 0,
      voteForProjectProposal: 0,
      withdrawProjectPayment: 0,
      getSurveyResults: 0,
      getSurveyInfo: 0,
      getSurveyOwner: 0,
      getIsProjectFunded: 0,
      getProjectNextPayment: 0,
      getProjectOwner: 0,
      getProjectInfo: 0,
      getNoOfProjectProposals: 0,
      getNoOfFundedProjects: 0,
      getEtherReceivedByProject: 0,
      getNoOfSurveys: 0,
    };
    for (let idx = 1; idx <= 60; idx++) {
      await MyGovContract.connect(addresses.at(-idx)).faucet();
    }

    for (let i = 8; i < numberOfUsers + 7; i++) {
      // console.log('idx', i);
      let addr8 = addresses[i];

      let tx = await MyGovContract.connect(addr8).faucet();
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null) gasCost.faucet += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).customFaucet(15);
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null) gasCost.customFaucet += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).submitSurvey(
        'CBsNLQmRAQB6YaCyidUdDnjFY5vQuiBrcqdyoWwxkF5',
        300,
        20,
        30,
        {
          value: ethers.utils.parseEther('0.04'),
        }
      );
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null) gasCost.submitSurvey += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).takeSurvey(1, [1, 0, 2]);
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null) gasCost.takeSurvey += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).submitProjectProposal(
        'CNSAQmRAQB6YaCyidP37UdDnjFY5vQuiBrcqdyoW1CuDgwxkD4',
        500 * 60 * 60 * 24,
        [7, 1, 3],
        [21, 39, 40],
        {
          value: ethers.utils.parseEther('0.1'),
        }
      );
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null)
        gasCost.submitProjectProposal += receipt.gasUsed.toNumber();
      tx = await MyGovContract.connect(addr8).delegateVoteTo(addr1.address, 2);
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null)
        gasCost.delegateVoteTo += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).donateEther({
        value: ethers.utils.parseEther('50'),
      });
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null) gasCost.donateEther += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).donateMyGovToken(1);
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null)
        gasCost.donateMyGovToken += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).voteForProjectPayment(
        i - 5,
        true
      );
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null)
        gasCost.voteForProjectPayment += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).voteForProjectProposal(
        i - 5,
        true
      );
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null)
        gasCost.voteForProjectProposal += receipt.gasUsed.toNumber();

      if (i >= 10) {
        await expect(
          MyGovContract.connect(addr8).reserveProjectGrant(i - 5)
        ).to.be.revertedWith('Project is not funded, cannot reserve a grant');
      }
      let proposal_needed_votes = numberOfUsers / 10 + 8;
      let payment_needed_votes = numberOfUsers / 100;

      for (let idx = 1; idx <= proposal_needed_votes; idx++) {
        await MyGovContract.connect(addresses.at(-idx)).voteForProjectProposal(
          i - 5,
          true
        );
      }
      for (let idx = 1; idx <= payment_needed_votes; idx++) {
        await MyGovContract.connect(addresses.at(-idx)).voteForProjectPayment(
          i - 5,
          true
        );
      }

      tx = await MyGovContract.connect(addr8).reserveProjectGrant(i - 5);
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null)
        gasCost.reserveProjectGrant += receipt.gasUsed.toNumber();

      tx = await MyGovContract.connect(addr8).withdrawProjectPayment(i - 5);
      receipt = await ethers.provider.getTransactionReceipt(tx.hash);
      if (receipt !== null)
        gasCost.withdrawProjectPayment += receipt.gasUsed.toNumber();
    }

    console.log(gasCost);
  };
  describe('Multiple User Test', function () {
    it('Testing with 400 users', async function () {
      await multipleUserTest(400);
    }).timeout(9990000000);
  });
});
