# SPOCRA Ballot Proposal
Submitting an official ballot proposal to the voting members should be done "on-chain" for the same sake of immutability and posterity that votes should also be cast on the chain.

## Proposed Ballot Proposal Format

```json
{
  "type": "object",
  "properties": {
    "NetworkId": {
      "type": "string",
      "required": true,
      "purpose": "Identify the voting 'network' this proposal belongs to",
      "example": "SPOCRA"
    },
    "ProposalId": {
      "type": "string",
      "required": true,
      "purpose": "Unique identifier (hash?) identifying this particular proposal",
      "example": "abc001ef"
    },
    "Title": {
      "type": "string",
      "required": true,
      "purpose": "The title of the ballot proposal",
      "example": "Creation Committee Election"
    },
    "Question": {
      "type": "string",
      "required": true,
      "purpose": "Describe what is being voted on",
      "example": "Who do you elect for the initial Creation Committee positions?"
    },
    "Description": {
      "type": "string",
      "required": false,
      "purpose": "Provide more in-depth description of the ballot proposal",
      "example": "The top seven (7) individuals will be selected to the initial Creation Committee with the two (2) runners-up serving as 'alternates' in the case of a Committee vacancy. You may vote for up to 3 nominees"
    },
    "ProposalURL": {
      "type": "url",
      "required": false,
      "purpose": "Provide a URL where more information about the proposal may live (maybe a forum for discussing pros and cons, etc)",
      "example": "https://wearecardano.io/proposals/abc001ef"
    },
    "VoteType": {
      "type": "string",
      "required": true,
      "purpose": "Define the type of vote (multiple choice, boolean, etc)",
      "example": "<boolean|multiple-choice|single-choice>"
    },
    "VoteLimit": {
      "type": "integer",
      "required": false,
      "purpose": "Define the number of votes an individual may cast in a multiple-choice vote",
      "example": 3
    },
    "VoteMultiple": {
      "type": "boolean",
      "required": false,
      "purpose": "Define whether or not a voter may vote for the same candidate more than once in a multiple-choice vote",
      "example": false
    },
    "VoteFee": {
      "type": "integer",
      "required": false,
      "purpose": "Optionally require that a fee (in Lovelaces) be sent to the address specified at VoteAddress in order to be counted.",
      "example": 1000000
    },
    "VoteAddr": {
      "type": "string",
      "required": false,
      "purpose": "Optionally specify the destination address that a vote should be sent to (i.e. --txn-out <VoteAddr>+<VoteFee>)",
      "example": "addr1v8ykqq055nss2eavrzlrc3mx8gq2sk84r3t80855ny7npmcd8qtuz"
    },
    "VoteOptions": {
      "type": "array",
      "required": false,
      "purpose": "Provide the list of voting options for single or multiple-choice votes",
      "items": {
        "type": "object",
        "properties": {
          "Name": {
            "type": "string",
            "required": true,
          },
          "Description": {
            "type": "string",
            "required": false,
          },
          "URL": {
            "type": "url",
            "required": false
          }
        }
      }
    }
  }
}
```