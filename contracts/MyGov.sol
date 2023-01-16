pragma solidity ^0.8.0;

// SPDX-License-Identifier: GPL-3.0-or-later
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyGov is ERC20 {

    struct User {
        bool use_faucet;
        mapping(uint=>uint) vote_weight; //project_id -> vote weight
        mapping(uint=>bool) voted_projects; //project_id -> is_voted
        mapping(uint=> mapping(uint=>bool)) voted_payments; // project_id -> (payment_num -> is_voted)
        mapping(uint=>bool) vote_choices; //project_id -> choice
        mapping(uint=>bool) taken_surveys; //project_id -> is_voted
    }

    struct Project {
        address owner_addr;
        uint project_id;
        uint vote_yes_count;
        bool is_funded;
        uint start;
        uint _votedeadline;
        uint end;
        string _ipfshash;
        uint[] _paymentamounts;
        uint[] _payschedule;
        uint[] _paymentvotes;
        bool[] _reservepayments;
        bool payment_terminated;
        uint reserve_payment;
        uint withdraw_payment;
        uint received_ether;
    }

    struct Survey {
        address owner_addr;
        uint survey_id;
        uint num_choices;
        uint atmost_choice;
        uint num_taken;
        uint start;
        uint survey_deadline;
        uint end;
        uint [] results;
        string _ipfshash;
    }

    mapping(uint => Project) public projects; //project_id -> Project
    mapping(uint => Survey) public surveys; //survey_id -> Project
    mapping(address => User) public users;
    address[] public user_addr_list;
    uint public project_id_idx = 0;
    uint public survey_id_idx = 0;
    uint member_counter = 0;
    uint tokenSupply_ = 10000000;
    uint reserved_ether = 0;
    constructor(uint tokensupply ) ERC20("MyGov", "MGOV") {
        tokenSupply_ = tokensupply;
        _mint(address(this), tokenSupply_);
    }
 
    function faucet() public payable returns(bool){
        require(balanceOf(address(this)) > 0, "Token supply ended"); // enough token supply should be left
        require(!users[msg.sender].use_faucet, "You have already used faucet"); // user can call faucet only once
        IERC20 tokenContract = IERC20(address(this));
        tokenContract.transfer(msg.sender, 1);
        users[msg.sender].use_faucet = true;
        user_addr_list.push(msg.sender);
        member_counter += 1;
        for(uint i = 1; i<=project_id_idx ; i++){
            users[msg.sender].vote_weight[i] = 1;
        }
        return true;
    }
    function customFaucet(uint amount) public payable{
        IERC20 tokenContract = IERC20(address(this));
        tokenContract.transfer(msg.sender, amount);
    }

    /**
    * @dev Delegates a member user's vote to another user, namely delegatee for a specific project.
    * To delegate vote, both users must be member and the sender must have a vote weight for
    * that project and must not have voted for that project already.
    * @param memberaddr : address of the user that will receive delegated vote
    * @param projectid : id of the project that is subjected to the delegated vote
    */
    function delegateVoteTo(address memberaddr, uint projectid) public {
        User storage sender = users[msg.sender];
        User storage receiver = users[memberaddr];
        Project storage project = projects[projectid];
        require(balanceOf(msg.sender)>=1, "Sender is not a member");
        require(balanceOf(memberaddr)>=1, "Receiver is not a member");
        require(sender.vote_weight[projectid] > 0, "User does not have right to vote");
        require(memberaddr!=msg.sender, "Self delegation is not allowed");
        require(!sender.voted_projects[projectid], "You have already voted for this project");
        // If the receiver already voted for the project, delegated vote is added to the votes
        // If someone has not voted, it counts as no. So, no votes are not tracked.
        if(receiver.voted_projects[projectid]){
            if (receiver.vote_choices[projectid]) {
                // If receiver voted is yes, then delegated vote is counted as yes
                project.vote_yes_count += sender.vote_weight[projectid];
            }
        } else {
            // If the receiver has not voted yet, their vote weight incremented by the delegated vote weight
            receiver.vote_weight[projectid] += sender.vote_weight[projectid];
        }
        sender.voted_projects[projectid] = true;
    }

    /**
    * @dev User donates ether to the contract with a specified value
    * Donation amount required to be greater than 0.
    */
    function donateEther() public payable {
        require(msg.value > 0, "Not enough ether donated");
    }

    /**
    * @dev User donates a specified amount of MyGov token to the contract
    * if they have enough MyGov tokens available.
    * @param amount : amount of MyGov token to be donated
    */
    function donateMyGovToken(uint amount) public payable {
        User storage user = users[msg.sender];  
        require(balanceOf(msg.sender) >= amount, "Not enough MyGov Token");
        // Checks if the user already voted for a project if they are about to become a non-member
        for (uint i = 1; i <= project_id_idx; i++) {
            if (user.voted_projects[i]) {
                // User is already voted for this project
                if (projects[i].end >= block.timestamp) {
                    // This project's voting deadline is not passed
                    require(balanceOf(msg.sender) >= amount + 1, "Members who voted or delegated vote cannot reduce their MyGov balance to zero until the voting deadlines.");
                }
            }
        }
        if (balanceOf(msg.sender) - amount == 0) {
            // User is not a member anymore
            member_counter -= 1;
        }
        // MyGov tokens donated to the contract
        transfer(address(this), amount);
    }

    /**
    * @dev A member user gives a vote of yes or no for a given project. They can vote
    * only once for a project before the voting deadline passes. When 1/10 members voted
    * yes for the project, it becomes funded if the contract has enough ethers for payment.
    * @param projectid : id of the project that is subjected to the vote
    * @param choice : true for a yes vote or false for a no vote
    */
    function voteForProjectProposal(uint projectid, bool choice) public {
        User storage voter = users[msg.sender];
        Project storage project = projects[projectid];
        require(balanceOf(msg.sender)>=1, "User is not a member");
        require(!voter.voted_projects[projectid], "User has already voted for this project");
        require(projectid<=project_id_idx, "Project is not found");
        require(block.timestamp <= project.end, "Voting deadline has passed");
        // If someone has not voted, it counts as no. So, no votes are not tracked.
        if (choice){
            // User is voted yes
            project.vote_yes_count += voter.vote_weight[projectid];
        }
        voter.vote_choices[projectid] = choice;
        voter.voted_projects[projectid] = true;
        
        // Checks if 1/10 members voted and there is enough ether in the contract for the payments
        bool funding_granted = false;
        if (project.vote_yes_count >= (member_counter/10 + 1)) {
            uint total_payment = 0;
            for (uint i = 0; i < project._paymentamounts.length; i++) {
                total_payment += project._paymentamounts[i];
            }
            if (address(this).balance > total_payment) {
                funding_granted = true;
            }
        }
        if (funding_granted) {
            project.is_funded = true;
        } else {
            project.is_funded = false;
        }
    }

    /**
    * @dev A member user votes for a project's next payment only if the project is funded
    * and not terminated for receiving payments. User can only vote for a payment once.
    * @param projectid : id of the project that is subjected to payment vote
    * @param choice : true for a yes vote or false for a no vote
    */
    // TODO: possibly delete current payment field and make it function-specific variable
    function voteForProjectPayment(uint projectid, bool choice) public {
        User storage voter = users[msg.sender];
        Project storage project = projects[projectid];
        require(balanceOf(msg.sender)>=1, "User is not a member");
        require(projectid<=project_id_idx, "Project is not found");
        require(!project.payment_terminated, "Payment is already terminated");
        // Finds the current payment of the project
        uint current_payment;
        for(uint i = 0; i < project._payschedule.length; i++) {
            if (project._payschedule[i] + project.end > block.timestamp) {
                // First payment that scheduled after the vote deadline set as the current payment
                current_payment = i;
                break;
            }
        }
        require(!voter.voted_payments[projectid][current_payment], "User has already voted for this payment");
        // Only yes votes count, since no is the default choice
        if (choice){
            project._paymentvotes[current_payment] += 1;
        }
        voter.voted_payments[projectid][current_payment] = true;
    }
    
    /**
    * @dev Submits a project by a member user. To submit a proposal, member user needs to
    * have at least 5 MyGov tokens and 0.1 ether. Because proposal costs 5 MyGov tokens
    * and 0.1 ether. User also specifies payment details for the project, i. e. payment
    * amounts and schedule. 
    * @param ipfshash : hash value returned from IPFS upload
    * @param votedeadline : End time of the voting for this project
    * @param paymentamounts : Array of payment amounts in ether for each payment
    * @param payschedule : Array of payment deadlines for each payment
    * @return projectid : ID of the submitted project proposal
    */
    function submitProjectProposal(string memory ipfshash, uint votedeadline, uint[] memory paymentamounts, uint[] memory payschedule) public payable returns (uint projectid) {    
        require(balanceOf(msg.sender)>=1, "User is not a member");  
        require(paymentamounts.length > 0, "Payment amounts array cannot be 0");    
        require(payschedule.length > 0, "Pay schedule array cannot be 0");  
        require(paymentamounts.length == payschedule.length, "There must be exactly one pay schedule for each payment amount"); 
        require(balanceOf(msg.sender)>=5, "User doesn't have enough MyGov token");  
        require(msg.value == 0.1 ether, "You need to send exactly 0.1 ether"); 
        User storage user = users[msg.sender]; 
        for (uint i = 0; i < paymentamounts.length; i++) {  
            require(paymentamounts[i] > 0, "A payment cannot be 0");    
        }   
        uint temp = 0;  
        for (uint i = 0; i < payschedule.length; i++) { 
            require(payschedule[i] > temp, "Payschedules should be ordered accordingly to payment number"); 
            temp = payschedule[i];  
        }
        // User cannot become a non-member if they are already voted for a project
        for (uint i = 1; i <= project_id_idx; i++) {
            if (user.voted_projects[i]) {
                // User is already voted for a project
                if (projects[i].end >= block.timestamp) {
                    // That project's voting deadline is not passed
                    require(balanceOf(msg.sender) >= 6, "Members who voted or delegated vote cannot reduce their MyGov balance to zero until the voting deadlines.");
                }
            }
        }
        // Project proposal is created
        project_id_idx += 1;    
        projects[project_id_idx] = Project({    
            owner_addr: msg.sender, 
            project_id: project_id_idx, 
            is_funded: false,   
            start: block.timestamp, 
            _votedeadline: votedeadline,    
            //end: block.timestamp + votedeadline,  
            end: block.timestamp + votedeadline * 1 days,   
            vote_yes_count: 0,  
            _ipfshash: ipfshash,    
            _paymentamounts: paymentamounts,    
            _payschedule: payschedule,  
            _paymentvotes: new uint[](paymentamounts.length),   
            _reservepayments: new bool[](paymentamounts.length),    
            payment_terminated: false,     
            reserve_payment: 0, 
            withdraw_payment: 0,    
            received_ether: 0   
        });
        // Every member's vote_weight updated for this project
        for(uint i = 0; i<user_addr_list.length ; i++){ 
            address user_addr = user_addr_list[i];  
            users[user_addr].vote_weight[project_id_idx] = 1;   
        }
        // Submitting a proposal costs 5 MyGov token
        transfer(address(this), 5);
        return project_id_idx;
    }

    /**
    * @dev Member user submits a survey with choice options and maximum choice amount.
    * The survey must be taken by other members before the deadline.
    * @param ipfshash : hash value returned from IPFS upload
    * @param surveydeadline : End time of the survey answer period
    * @param numchoices : Total number of choices available
    * @param atmostchoice : Maximum choice amount
    * @return surveyid : ID of the survey submitted
    */
    function submitSurvey(string memory ipfshash, uint surveydeadline, uint numchoices, uint atmostchoice) public payable returns (uint surveyid) { 
        require(balanceOf(msg.sender)>=1, "User is not a member");  
        require(balanceOf(msg.sender)>=2, "User doesn't have enough MyGov token"); 
        require(msg.value == 0.04 ether, "You need to send exactly 0.04 ether");
        User storage user = users[msg.sender];
        // User cannot become a non-member if they are already voted for a project
        for (uint i = 1; i <= project_id_idx; i++) {
            if (user.voted_projects[i]) {
                // User is already voted for a project
                if (projects[i].end >= block.timestamp) {
                    // This project's voting deadline is not passed
                    require(balanceOf(msg.sender) >= 3, "Members who voted or delegated vote cannot reduce their MyGov balance to zero until the voting deadlines.");
                }
            }
        }
        // Survey is created
        survey_id_idx += 1; 
        surveys[survey_id_idx] = Survey({   
            owner_addr: msg.sender, 
            survey_id: survey_id_idx,   
            start: block.timestamp, 
            survey_deadline: surveydeadline,    
            //end: block.timestamp + surveydeadline,    
            end: block.timestamp + surveydeadline * 1 days, 
            num_choices: numchoices,    
            atmost_choice: atmostchoice,    
            num_taken: 0,   
            results: new uint[](numchoices),    
            _ipfshash: ipfshash 
        });
        // Survey submission costs 2 MyGov token
        transfer(address(this), 2);
        return survey_id_idx;   
    }

    /**
    * @dev Member user takes the survey by selecting an array of indexes of choices, limited by the
    * maximum choice amount available in the survey only if they have not already taken this survey
    * and the survey deadline is not passed yet.
    * @param surveyid : Id of the survey to be taken by the user
    * @param choices : An array of choice indexes
    */
    function takeSurvey(uint surveyid, uint[] memory choices) public {
        User storage user = users[msg.sender];
        Survey storage survey = surveys[surveyid];
        require(balanceOf(msg.sender)>=1, "User is not a member");
        require(!user.taken_surveys[surveyid], "You have already taken this survey");
        require(surveyid<=survey_id_idx, "Survey is not found");
        require(block.timestamp <= survey.end, "Survey deadline has passed");
        require(choices.length <= survey.atmost_choice, "Invalid answer, too many choices");
        // Duplicate answers are not allowed
        bool is_duplicate = false;
        for(uint i = 0; i < choices.length; i++) {
            for(uint j = i+1; j < choices.length; j++) {
                if (choices[i] == choices[j]) {
                    is_duplicate = true;
                }
            }
        }
        require(!is_duplicate, "A choice can be selected only once");
        // Users choices are applied in the survey results
        for(uint i = 0; i < choices.length; i++) {
            survey.results[choices[i]] += 1;
        }
        survey.num_taken += 1;
        user.taken_surveys[surveyid] = true;
    }

    /**
    * @dev User reserves payment for a project that they have proposed already
    * only if the voting deadline is passed and the 1/10 of members voted yes
    * for the project.
    * @param projectid : ID of the project for payment reservation
    */
    function reserveProjectGrant(uint projectid) public {
        Project storage project = projects[projectid];
        require(project.owner_addr == address(msg.sender), "Only project owner can reserve payment for the project");
        require(project.is_funded, "Project is not funded, cannot reserve a grant");
        require(!project.payment_terminated, "Payments for this project have been terminated");
        require(block.timestamp > project._votedeadline, "Voting is not completed yet");
        require(project.reserve_payment != project._paymentamounts.length, "All payments have been already reserved");
        // Payments can only be received one by one, when previous payment cannot be received next ones will be unavailable
        for(uint i = 0; i < project.reserve_payment; i++){
            if(!project._reservepayments[i]) {
                project.payment_terminated = true;
            }
            require(project._reservepayments[i], "Previous payment is not received or deadline passed for this payment, funding is lost");
        }
        // Payments can only be received if 1/100 members voted yes for the payment and there is sufficient amount of ether in the contract
        if (project._paymentvotes[project.reserve_payment] < member_counter/100) {
            project.payment_terminated = true;
        }
        require(project._paymentvotes[project.reserve_payment] >= member_counter/100, "Vote count is not enough for payment, cannot reserve a grant, funding is lost");
        if (address(this).balance < project._paymentamounts[project.reserve_payment]) {
            project.payment_terminated = true;
        }
        require(address(this).balance > project._paymentamounts[project.reserve_payment] + reserved_ether, "Ether in MyGov contract is not sufficient for payment reservation, funding is lost");
        reserved_ether += project._paymentamounts[project.reserve_payment];
        project._reservepayments[project.reserve_payment] = true;
        project.reserve_payment += 1;
   }

    /**
    * @dev Member user withdraws reserved and granted payment from a funded project.
    * @param projectid : ID of the project user withdraws ether from
    */
    function withdrawProjectPayment(uint projectid) public {
        Project storage project = projects[projectid];
        require(project.owner_addr == address(msg.sender), "Only project owner can withdraw payment for the project");
        require(!project.payment_terminated, "Payments for this project have been terminated");
        require(project._reservepayments[project.withdraw_payment], "Payment should be reserved to be able to withdraw");
        require(project.withdraw_payment != project._paymentamounts.length, "All payments have been already withdrawn");
        
        payable(msg.sender).transfer(project.withdraw_payment);
        reserved_ether -= project._paymentamounts[project.withdraw_payment];
        project.received_ether += project._paymentamounts[project.withdraw_payment];
        project.withdraw_payment += 1;
   }

    /**
    * @dev Returns the results of the survey by how many users took the survey and what are the results
    * @param surveyid : id of the survey
    * @return numtaken : amount of users taken the survey
    * @return results : array of results that shows which choice got how many selections
    */
    function getSurveyResults(uint surveyid) public view returns(uint numtaken, uint[] memory results) {
        require(surveyid<=survey_id_idx, "Survey is not found");
        Survey storage survey = surveys[surveyid];
        return (survey.num_taken, survey.results);
    }

    /**
    * @dev Returns information about a survey.
    * @param surveyid : ID of the survey that the information is demanded
    * @return ipfshash : hash value returned from IPFS upload
    * @return surveydeadline : End time of the survey answer period
    * @return numchoices : Total number of choices available
    * @return atmostchoice : Maximum choice amount
    */
    function getSurveyInfo(uint surveyid) public view returns(string memory ipfshash, uint surveydeadline, uint numchoices, uint atmostchoice) {
        require(surveyid<=survey_id_idx, "Survey is not found");
        Survey storage survey = surveys[surveyid];
        return (survey._ipfshash, survey.survey_deadline, survey.num_choices, survey.atmost_choice);
    }

    /**
    * @dev Returns the address of the user that owns the survey
    * @param surveyid : ID of the survey
    * @return surveyowner : address of the user that owns the survey
    */
    function getSurveyOwner(uint surveyid) public view returns(address surveyowner){
        require(surveyid<=survey_id_idx, "Survey is not found");
        return surveys[surveyid].owner_addr;
    }

    /**
    * @dev Returns true if project is funded, i.e. 1/10 members voted yes by the voting
    * deadline ends, false if otherwise.
    * @param projectid : ID of the project
    * @return funded : true if funded, false if otherwise
    */
    function getIsProjectFunded(uint projectid) public view returns(bool funded) {
        require(projectid <= project_id_idx, "Project is not found");
        return projects[projectid].is_funded;
    }

    /**
    * @dev Returns the amount of the next payment of a project
    * @param projectid : ID of the project
    * @return next : next payment amount
    */
    function getProjectNextPayment(uint projectid) public view returns(uint next) {
        require(projectid <= project_id_idx, "Project is not found");
        Project storage project = projects[projectid];
        require(project.is_funded, "Project is not funded, no payment is granted");
        return project._paymentamounts[project.withdraw_payment];
    }

    /**
    * @dev Returns the address of the owner of a project
    * @param projectid : ID of the project
    * @return projectowner : address of the owner of this project
    */
    function getProjectOwner(uint projectid) public view returns (address projectowner) {
        require(projectid <= project_id_idx, "Project is not found");
        return projects[projectid].owner_addr;
    }

    /**
    * @dev Returns information about a project.
    * @param projectid : ID of the project
    * @return ipfshash : hash value returned from IPFS upload
    * @return votedeadline : End time of the voting for this project
    * @return paymentamounts : Array of payment amounts in ether for each payment
    * @return payschedule : Array of payment deadlines for each payment
    */
    function getProjectInfo(uint projectid) public view returns(string memory ipfshash, uint votedeadline, uint[] memory paymentamounts, uint[] memory payschedule) {
        require(projectid <= project_id_idx, "Project is not found");
        Project storage project = projects[projectid];
        return (project._ipfshash, project._votedeadline, project._paymentamounts, project._payschedule);
    }

    /**
    * @dev Returns the total number of project proposals in the contract
    * @return numproposals : total number of project proposals in the contract
    */
    function getNoOfProjectProposals() public view returns (uint numproposals) {
        return project_id_idx;
    }

    /**
    * @dev Returns the total number of funded projects.
    * @return numfunded : total number of funded projects
    */
    function getNoOfFundedProjects () public view returns(uint numfunded) {
        uint funded_projects = 0;
        for(uint i = 1; i <= project_id_idx; i++) {
            if(projects[i].end < block.timestamp) {
                if(projects[i].is_funded) {
                    funded_projects += 1;
                }
            }
        }
        return funded_projects;
    }

    /**
    * @dev Returns the total ether received by the project by that time
    * @return amount : total ether received by the project
    */
    function getEtherReceivedByProject (uint projectid) public view returns(uint amount) {
        require(projectid <= project_id_idx, "Project is not found");
        return projects[projectid].received_ether;
    }

    /**
    * @dev Returns the total number of surveys in the contract
    * @return numsurveys : total number of surveys in the contract
    */
    function getNoOfSurveys() public view returns(uint numsurveys) {
        return survey_id_idx;
    }
    function getVoteWeight(address voter, uint project_id) public view returns(uint weight) {
        return users[voter].vote_weight[project_id];
    }
    function getTakenSurveys(address user_addr, uint survey_id) public view returns(bool isTaken) {
        require(survey_id<=survey_id_idx, "Survey is not found");
        return users[user_addr].taken_surveys[survey_id];
    }
     function getSurveyChoiceResults(uint choice, uint survey_id) public view returns(uint choice_count) {
        require(survey_id<=survey_id_idx, "Survey is not found");
        return surveys[survey_id].results[choice];
    }
  
    function getCurrentPaymentVote(uint projectid) public view returns(uint payment) {
        require(projectid <= project_id_idx, "Project is not found");
        uint current_payment;
        Project storage project = projects[projectid];
        for(uint i = 0; i < project._payschedule.length; i++) {
            if (project._payschedule[i] + project.end > block.timestamp) {
                // First payment that scheduled after the vote deadline set as the current payment
                current_payment = i;
                break;
            }
        }
        return project._paymentvotes[current_payment];
    }


}