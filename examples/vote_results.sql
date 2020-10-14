/*****************************************************************************************************************************
* 
* This is an example of how to get vote results out of an instance of cardano-db-sync
* These queries were run against db-sync 5.0.1 to tally results of SPOCRA votes 1 and 2
* 
* This is  a second independant vote-counting implementation developed for the SPOCRA vote to validate
*  results from the SPOCRA voting application
* 
* In order to run this script yourself, run this script in it's entirety on a cardano-db-sync postgres database. 
*  this will build the new SPOCRA schema and multiple views which will calculate view results
* 
* Prerequsities:
* 	In order to accurately validate candidates, you will need to insert the valid voter ids into the registered_voters table 
* 		this list will not be public until after the voting has completed.
*
******************************************************************************************************************************/


----------------------------------------------
-- Create necessary objects
----------------------------------------------
CREATE SCHEMA IF NOT EXISTS spocra
    AUTHORIZATION postgres;

CREATE TABLE IF NOT EXISTS spocra.registered_voters
(
    voter_id character varying COLLATE pg_catalog."default" NOT NULL,
    proposal_id character varying COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT registered_voters_pkey PRIMARY KEY (voter_id, proposal_id)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE spocra.registered_voters
    OWNER to postgres;

-----------------------------------------------------
-- Populate registered voters from on chain record
-- will populate for all proposals
-----------------------------------------------------

insert into spocra.registered_voters
select 
	tm.json ->> 'ProposalId' as proposal_id,
	jsonb_array_elements_text(cast(tm.json ->> 'Voters' as jsonb))  as arr
from tx_metadata tm		
where tm.json->> 'ObjectType' = 'VoteRegistration'
	and tm.json ->> 'NetworkId' = 'SPOCRA';

---------------------------------------------
-- proposal - main proposals view
---------------------------------------------
	create or replace view spocra.v_proposals
	as 
	select 
		tm.json ->> 'Title' as title,
		tm.json ->> 'Question' as question,
		tm.json ->> 'NetworkId' as network_id,
		tm.json ->> 'VoteType' as vote_type,
		tm.json ->> 'VoteLimit' as vote_limit,
		tm.json ->> 'ProposalId' as proposal_id,
		tm.json ->> 'VoterHash' as voter_hash,
		tm.json ->> 'VoteRanked' as vote_ranked,
		tm.json ->> 'Description' as description,
		tm.json ->> 'ProposalUrl' as proposal_url,
		tm.json ->> 'VoteStartPeriod' as vote_start_period,
		tm.json ->> 'VoteEndPeriod' as vote_end_period
	from tx_metadata tm
	where tm.json->> 'ObjectType' = 'VoteProposal'
		and tm.json ->> 'NetworkId' = 'SPOCRA';

---------------------------------------------
-- candidates - List of Candidates
---------------------------------------------

	create or replace view spocra.v_candidates
	as
	select 
		opt."CandidateId" as candidate_id,
		opt."Name" as name,
		opt."Description" as description,
		opt."URL" as url,
		v.proposal_id
	from tx_metadata tm,
		jsonb_to_recordset(cast( tm.json ->> 'VoteOptions' as jsonb))
			as opt("CandidateId"  varchar, "URL" varchar, "Name" varchar, "Description" varchar),
		spocra.v_proposals v 
	where tm.json->> 'ObjectType' = 'VoteProposal'
		and tm.json ->> 'NetworkId' = v.network_id
		and tm.json ->> 'ProposalId' = v.proposal_id;

------------------------------------------------------
-- ballot_raw - Ballot entries - not parsed yet
------------------------------------------------------
	create or replace view spocra.v_ballot_raw
	as
	select 
		tm.tx_id,
		tm.json ->> 'ProposalId' as proposal_id,
		cast( t.hash as varchar) as hash,
		tm.json ->> 'VoterId' as voter_id,
		b.block_no,
		b.epoch_no,
		b.slot_no,
		b.time,
		t.fee,
		t.out_sum,
		t.size,
		tm.json ->> 'Choices' as choices,
		tm.key
	from tx_metadata tm
		inner join tx t on t.id = tm.tx_id
		inner join block b on t.block = b.id
	where tm.json->> 'ObjectType' = 'VoteBallot';


------------------------------------------------------------------------------
-- v_ballot_entry_base - Individual ballot entries - multiple per vote cast
------------------------------------------------------------------------------

    -- there appears to be 2 formats of ballot, hence we need to union 2 queries
    -- first, there is the array of choices
	-- next we have the 'object' of choices with an arbitrary numeric key
	create or replace view spocra.v_ballot_entry_base
	as
	select *
	from (
		select b.*,
			row_number() over (partition by tx_id) choice_index,
			c."CandidateId" as candidate_id,
			c."VoteRank"  as vote_rank,
			c."VoteWeight"  as vote_weight 
		from spocra.v_ballot_raw b,
			jsonb_to_recordset(cast(b.choices as jsonb)) as c("CandidateId" varchar, "VoteRank" int, "VoteWeight" int )
		where jsonb_typeof(cast(b.choices as jsonb)) = 'array'
			-- this was 2 bad ballots - breaks parsing rules
			and b.choices not like '[[%'

		union all

		select b.*,
			cast(c.key as int) as choice_index,
			c.value ->> 'CandidateId' as candidate_id,
			cast(c.value ->> 'VoteRank' as int) as vote_rank,
			cast(c.value ->> 'VoteWeight' as int) as vote_weight 
		from spocra.v_ballot_raw b,
			jsonb_each(cast(b.choices as jsonb)) c
		where jsonb_typeof(cast(b.choices as jsonb)) = 'object'

	) a;


------------------------------------------------------------------------------
-- v_ballot_entry - Individual ballot entries with some additional validation flags added
------------------------------------------------------------------------------
/* 
	1. Check if the vote was received within the valid voting window 
	2. Check that the Voter ID exists in the Voter Registration rolls
	3. Check if the Voter has aleady voted (checked later at the ballot level)
	4. Check if the ballot contains at least one valid vote, discard if voting preference is empty
	5. Check if the ballot contains more than the maximum number of votes, discard if votes cast exceeds the VoteLimit of the proposal
*/

	create or replace view spocra.v_ballot_entry
	as
	select 
		b.*,
		-- vote score - this adds the weightings
		case 
			when b.vote_rank = 1 then 3
			when b.vote_rank = 2 then 2
			when b.vote_rank = 3 then 1
		end as vote_score,
		-- validation flags
		case 
			when b.epoch_no >= cast(p.vote_start_period as int) AND b.epoch_no <= cast(p.vote_end_period as int)
				THEN 1 else 0
			end as is_within_epochs, -- is this in epoch 218 or 219?
		case when sum(vote_weight) over (partition by tx_id, key) <= cast(p.vote_limit as int) then 1 else 0 end as is_within_limit, -- have they cast more than 3 votes
		case when cast(b.vote_weight as int) > 1 then 0 else 1 end as is_vote_weight_valid, -- have they given an entry a weight of more than 1?
		case when rv.voter_id is null then 0 else 1 end as is_registered_voter -- is this person in our list of registered voters?
	--into spocra.v_ballot_entry
	from spocra.v_ballot_entry_base b
		left join spocra.v_proposals p on p.proposal_id = b.proposal_id
		left join spocra.registered_voters rv on replace(lower(ltrim(rtrim(b.voter_id))), '-', '') =  replace(lower(ltrim(rtrim(rv.voter_id))), '-', '')
			and rv.proposal_id = b.proposal_id;
	


---------------------------------------------------------------------------------------------------------------
-- v_vote_validation - This rolls up the vote to the ballot level and determines validity based on flags in the ballot entries
-- 	this also adds a vote_num which indicates which vote this is for an individual voter_id 
-- 		only the first vote (vote_num = 1) is counted
----------------------------------------------------------------------------------------------------------------
	create or replace view spocra.v_vote_validation
	as
	select 
		*,
		row_number() over (partition by proposal_id, voter_id order by is_ballot_valid desc, slot_no) as vote_num
	from (
		select 
			tx_id,
			voter_id,
			slot_no,
			hash,
			proposal_id,
			case 
				when 
					min(is_within_epochs) > 0 and  -- 
					min(is_within_limit) >  0 and -- 3 or less votes
					min(is_vote_weight_valid) > 0 and	-- no single weight > 1
					count(distinct candidate_id) = count(candidate_id) and -- no double voting for same candidate
					min(is_registered_voter) > 0 -- registered_voter
				then 1
				else 0
			end as is_ballot_valid -- this ballot follows all the rules (still might be discarded if it's not the first valid vote)		
		from spocra.v_ballot_entry a
		group by 
			tx_id,
			voter_id,
			slot_no,
			hash,
			proposal_id
	) a;


----------------------------------------------------------------------------------------
-- FINAL vote table - append all flags, validation and scores 
-- 	- make final decision if this should be counted based on order of valid votes
-- - the granularity of this table is the individual candidate vote - multiple records per ballot
-----------------------------------------------------------------------------------------

	create or replace view spocra.v_vote
	as
	select 
		b.tx_id,
		b.proposal_id,
		case when b.proposal_id = '00d8f63b-9efb-41b6-90dc-35d90f5ad4e2' then 'vote 1' 
			when b.proposal_id = '9cdb445e-b2ce-4922-8272-4b8549b823d2' then 'vote 2'
			else 'other'
			end as vote_name,
		b.hash,
		b.voter_id,
		b.block_no,
		b.epoch_no,
		b.slot_no,
		b."time",
		b.fee,
		b.out_sum,
		b.size,

		-- validation flags
		b.is_within_epochs,
		b.is_within_limit,
		b.is_vote_weight_valid,
		b.is_registered_voter,
		vvr.is_ballot_valid,
		vvr.vote_num,
		case when vvr.is_ballot_valid = 1 and vvr.vote_num = 1 then 1 else 0 end as is_vote_counted, -- this is the master flag - are we counting this or not?

		-- choices
		b.choices as raw_choices,
		b.choice_index,
		b.candidate_id,
		b.vote_rank,
		b.vote_weight,
		b.vote_score,
		c.name as candidate_name,
		c.description as candidate_description,
		c.url as candidate_url,
		current_timestamp as data_as_of
		
	from spocra.v_vote_validation vvr
		left join spocra.v_ballot_entry b on vvr.tx_id = b.tx_id and b.voter_id = vvr.voter_id
		left join  spocra.v_candidates c on b.candidate_id = c.candidate_id;


-- now bask in the magic!
select *
from spocra.v_vote


-----------------------------
-- Final Results:
-----------------------------
select 	
	candidate_id, 
	candidate_name, 
	count(*) as total_votes,
	count(case when vote_rank = 1 then 1 else null end) as rank1_votes,
	count(case when vote_rank = 2 then 1 else null end) as rank2_votes,
	count(case when vote_rank = 3 then 1 else null end) as rank3_votes,
	sum(vote_score) as total_score
from spocra.v_vote
where is_vote_counted = 1
	and vote_name = 'vote 2'
group by candidate_id, 
	candidate_name
order by total_score desc;


-----------------------------------
-- Count of voters
----------------------------------
select distinct voter_id
from spocra.v_vote
where is_vote_counted = 1
	and vote_name = 'vote 2'