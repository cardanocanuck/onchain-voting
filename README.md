# SPOCRA On-Chain Voting
The purpose of this repository is to describe and outline the process of submitting ballot proposals and casting votes onto the Cardano blockchain.

While the initial intent of this outline is to allow voting for the SPOCRA organization, the functionality and packages described here should be easily adaptable to serve other purposes.

## High-Level Concept
The basic premise of this idea is that a group or entity can submit a "ballot proposal" to the blockchain and all eligible voters may similarly submit to cast their votes, storing them in the immutable ledger of the blockchain.

`cardano-cli` makes this possible via inclusion of the `--metadata-json-file FILE` command line argument.

By using this properly structured JSON format we can submit "meta" data to the chain and (at current) query it back out again via the `cardano-db-sync` PostgreSQL interface.

In this way we can easily query for all "votes" cast on the chain to arrive at a final result.

## SPOCRA Voting
Aside from just a simple poll, organizations such as SPOCRA will require some means of voter authentication as well as a limited time window to vote. This can be accomplished and queried from the chain using JSON metadata attributes.

The structure and format of this JSON specification will be an on-going development process as SPOCRA hones and refines its needs.
